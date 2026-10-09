# WBNS e-Document — Production Smoke Test

## 1. Login / Identity
- [ ] Admin login succeeds
- [ ] Normal staff login succeeds
- [ ] Inactive profile cannot use application permissions
- [ ] Permission list loads

## 2. User / Department / Role
- [ ] Admin can create/edit department
- [ ] Admin can activate/deactivate department
- [ ] Admin can assign department to a profile
- [ ] Admin can add/remove role
- [ ] Admin can activate/deactivate user
- [ ] Invitation resend works
- [ ] Excel import validates duplicate email/employee code
- [ ] Excel import rejects inactive/nonexistent department

## 3. Incoming document
- [ ] Create/register incoming document
- [ ] Registered number generated correctly
- [ ] Attach Google Drive file with a user who has `document.update`
- [ ] User without `document.update` is rejected before a Drive upload occurs
- [ ] File version increments v1 → v2
- [ ] Only one current version exists
- [ ] Assign document
- [ ] Set deadline
- [ ] Complete workflow
- [ ] Archive workflow

## 4. Outgoing document
- [ ] Create outgoing document
- [ ] Submit approval
- [ ] Approver can approve/reject/return
- [ ] Approved → sent
- [ ] Sent → archived

## 5. Notifications
- [ ] In-app notification appears
- [ ] Read/unread state works
- [ ] Browser Push subscription can be registered after VAPID public key is configured
- [ ] Push delivery is tested after VAPID private key is configured as a Supabase secret

## 6. Security
- [ ] Anonymous client cannot call admin RPCs
- [ ] Staff cannot modify another user's role/department
- [ ] Staff cannot bypass workflow transition guards
- [ ] `document.update` alone cannot complete or archive a document
- [ ] `document.complete` is required for the `completed` transition
- [ ] `document.archive` is required for the `archived` transition
- [ ] `document.assign` is required for direct transition to `assigned`; normal assignment uses the assignment RPC
- [ ] RLS blocks unauthorized document access
- [ ] Audit log records admin/security-sensitive changes

## 7. PWA / Browser
- [ ] Chrome desktop install
- [ ] Android Chrome install
- [ ] iOS Safari home-screen test
- [ ] Refresh/deep-link route does not return GitHub Pages 404
- [ ] Offline shell opens
- [ ] Reconnect returns to live data

## 8. Backup / Recovery
- [ ] Database backup/export completed
- [ ] Google Drive document backup policy verified
- [ ] Restore to a non-production target tested
- [ ] Recovery owner and recovery credentials documented securely
