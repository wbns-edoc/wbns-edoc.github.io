import { createSupabaseContext } from "npm:@supabase/server@1";

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers });
    const { data: ctx, error: authError } = await createSupabaseContext(req, { auth: "user" });
    if (authError) return new Response(JSON.stringify({ ok:false, code:"unauthorized" }), { status:authError.status, headers });
    try {
      const body = await req.json();
      const rows = Array.isArray(body?.rows) ? body.rows : [];
      if (!rows.length) return new Response(JSON.stringify({ ok:false, code:"rows_required" }), { status:400, headers });
      if (rows.length > 200) return new Response(JSON.stringify({ ok:false, code:"max_200_rows" }), { status:400, headers });

      const { data: perms, error: permError } = await ctx.supabase.rpc("get_my_permissions");
      if (permError) throw new Error("permission_check_failed");
      const codes = new Set<string>((perms ?? []).map((x: any) => String(x.permission_code ?? "")));
      const hasRoleAssignment = rows.some((row: any) => String(row?.role ?? "").trim().length > 0);
      const { authorizeUserImport } = await import("./authorization.ts");
      const authorization = authorizeUserImport({
        action: "import",
        permissionCodes: codes,
        hasRoleAssignment,
      });
      if (!authorization.allowed) {
        return new Response(JSON.stringify({ ok:false, code:"insufficient_privilege", reason:authorization.reason }), { status:403, headers });
      }

      const admin = ctx.supabaseAdmin;
      const actorId = String((ctx.userClaims as unknown as { sub?: string } | undefined)?.sub ?? "");
      const results: any[] = [];

      for (let i = 0; i < rows.length; i++) {
        const r = rows[i] ?? {};
        const rowNo = Number(r.row ?? i + 1);
        const email = String(r.email ?? "").trim().toLowerCase();
        const fullName = String(r.full_name ?? "").trim();
        const employeeCode = String(r.employee_code ?? "").trim() || null;
        const phone = String(r.phone ?? "").trim() || null;
        const departmentName = String(r.department ?? "").trim();
        const roleValue = String(r.role ?? "").trim();
        const isActive = r.is_active !== false;

        if (!fullName || !email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
          results.push({ row: rowNo, status:"error", code:"invalid_required_fields" });
          continue;
        }

        let departmentId: string | null = null;
        if (departmentName) {
          const dep = await admin.from("departments").select("id").or(
            "code.ilike." + departmentName.replace(/,/g, "") + ",name.ilike." + departmentName.replace(/,/g, "")
          ).limit(2);
          if (dep.error) {
            results.push({ row: rowNo, status:"error", code:"department_lookup_failed" });
            continue;
          }
          if ((dep.data ?? []).length > 1) {
            results.push({ row: rowNo, status:"error", code:"department_ambiguous" });
            continue;
          }
          if ((dep.data ?? []).length === 1) departmentId = dep.data[0].id;
          else {
            results.push({ row: rowNo, status:"error", code:"department_not_found" });
            continue;
          }
        }

        let roleId: string | null = null;
        if (roleValue) {
          const role = await admin.from("roles").select("id").or(
            "code.ilike." + roleValue.replace(/,/g, "") + ",name.ilike." + roleValue.replace(/,/g, "")
          ).limit(2);
          if (role.error || (role.data ?? []).length > 1) {
            results.push({ row: rowNo, status:"error", code: role.error ? "role_lookup_failed" : "role_ambiguous" });
            continue;
          }
          if ((role.data ?? []).length === 1) roleId = role.data[0].id;
          else {
            results.push({ row: rowNo, status:"error", code:"role_not_found" });
            continue;
          }
        }

        let profile: any = null;
        if (employeeCode) {
          const byCode = await admin.from("profiles").select("id,email,employee_code").eq("employee_code", employeeCode).maybeSingle();
          if (byCode.error) {
            results.push({ row: rowNo, status:"error", code:"profile_lookup_failed" });
            continue;
          }
          profile = byCode.data;
        }
        if (!profile) {
          const byEmail = await admin.from("profiles").select("id,email,employee_code").ilike("email", email).maybeSingle();
          if (byEmail.error) {
            results.push({ row: rowNo, status:"error", code:"profile_lookup_failed" });
            continue;
          }
          profile = byEmail.data;
        }

        let userId = profile?.id ?? null;
        let action = "updated";

        if (!userId) {
          const invited = await admin.auth.admin.inviteUserByEmail(email, {
            data: { full_name: fullName, employee_code: employeeCode },
          });
          if (invited.error || !invited.data?.user?.id) {
            results.push({ row: rowNo, status:"error", code:"auth_invite_failed", message: invited.error?.message ?? "invite_failed" });
            continue;
          }
          userId = invited.data.user.id;
          action = "invited";
        }

        const upsert = await admin.from("profiles").upsert({
          id: userId,
          employee_code: employeeCode,
          full_name: fullName,
          email,
          phone,
          department_id: departmentId,
          is_active: isActive,
        }, { onConflict:"id" });
        if (upsert.error) {
          results.push({ row: rowNo, status:"error", code:"profile_upsert_failed", message: upsert.error.message });
          continue;
        }

        if (roleId) {
          const roleWrite = await admin.from("user_roles").upsert({
            user_id:userId,
            role_id:roleId,
            assigned_by:actorId || null,
          }, { onConflict:"user_id,role_id" });
          if (roleWrite.error) {
            results.push({ row: rowNo, status:"error", code:"role_assign_failed", message:roleWrite.error.message });
            continue;
          }
        }

        await admin.from("audit_logs").insert({
          actor_id: actorId || null,
          action: "user_import_" + action,
          entity_type: "profiles",
          entity_id: userId,
          new_data: { employee_code: employeeCode, full_name: fullName, email, role: roleValue || null },
        });

        results.push({ row: rowNo, status:"ok", action, user_id:userId });
      }

      const summary = {
        invited: results.filter(x => x.action === "invited").length,
        updated: results.filter(x => x.action === "updated").length,
        errors: results.filter(x => x.status === "error").length,
      };
      return new Response(JSON.stringify({ ok:true, summary, results }), { status:200, headers });
    } catch {
      return new Response(JSON.stringify({ ok:false, code:"internal_error" }), { status:500, headers });
    }
});
