import React from 'react';
import { createRoot } from 'react-dom/client';
import { createClient } from '@supabase/supabase-js';
import './styles.css';

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;
export const supabase = url && key ? createClient(url,key) : null;

if ('serviceWorker' in navigator) window.addEventListener('load',()=>navigator.serviceWorker.register('/sw.js').catch(()=>{}));

function App(){
  const [email,setEmail]=React.useState('');
  const [password,setPassword]=React.useState('');
  const [session,setSession]=React.useState<any>(null);
  const [error,setError]=React.useState('');
  React.useEffect(()=>{
    if(!supabase)return;
    supabase.auth.getSession().then(({data})=>setSession(data.session));
    const {data}=supabase.auth.onAuthStateChange((_e,s)=>setSession(s));
    return ()=>data.subscription.unsubscribe();
  },[]);
  async function signIn(e:React.FormEvent){
    e.preventDefault();setError('');
    if(!supabase){setError('ยังไม่ได้ตั้งค่า Supabase environment variables');return;}
    const {error}=await supabase.auth.signInWithPassword({email,password});
    if(error)setError('อีเมลหรือรหัสผ่านไม่ถูกต้อง');
  }
  async function signOut(){await supabase?.auth.signOut();}
  if(!session) return <main className="login"><section className="card"><div className="brand">WBNS</div><h1>ระบบสารบรรณอิเล็กทรอนิกส์</h1><p>โรงเรียนวัดบึงน้ำใส</p><form onSubmit={signIn}><label>อีเมล<input value={email} onChange={e=>setEmail(e.target.value)} type="email" required autoComplete="username"/></label><label>รหัสผ่าน<input value={password} onChange={e=>setPassword(e.target.value)} type="password" required autoComplete="current-password"/></label>{error&&<div className="error">{error}</div>}<button>เข้าสู่ระบบ</button></form></section></main>;
  return <main className="app"><header><div><strong>WBNS e-Document</strong><span>ระบบสารบรรณอิเล็กทรอนิกส์ โรงเรียนวัดบึงน้ำใส</span></div><button className="secondary" onClick={signOut}>ออกจากระบบ</button></header><section className="content"><h2>Dashboard</h2><div className="grid"><article><b>หนังสือรับ</b><strong>0</strong><span>รอดำเนินการ</span></article><article><b>หนังสือส่ง</b><strong>0</strong><span>ร่าง / รอส่ง</span></article><article><b>งานของฉัน</b><strong>0</strong><span>งานที่ได้รับมอบหมาย</span></article><article><b>ใกล้ครบกำหนด</b><strong>0</strong><span>ต้องติดตาม</span></article></div></section></main>
}
createRoot(document.getElementById('root')!).render(<React.StrictMode><App/></React.StrictMode>);