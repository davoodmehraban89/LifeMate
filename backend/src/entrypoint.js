process.env.NODE_ENV = 'test';
const { app, pool } = await import('./server.js');
const { createPhase4Router } = await import('./phase4.js');
import jwt from 'jsonwebtoken';
const jwtSecret=process.env.JWT_SECRET;
async function auth(req,res,next){const raw=req.headers.authorization?.replace(/^Bearer\s+/i,'');try{const identity=jwt.verify(raw,jwtSecret,{audience:'lifemate-api',issuer:'lifemate'});const session=await pool.query('select 1 from auth_session where id=$1 and user_id=$2 and revoked_at is null and expires_at>now()',[identity.sid,identity.sub]);if(!session.rowCount)return res.status(401).json({error:'session_invalid'});req.identity=identity;next()}catch{return res.status(401).json({error:'unauthorized'})}}
app.use('/v1',createPhase4Router({pool,auth}));
const port=Number(process.env.PORT??8080);
app.listen(port,()=>console.log(`LifeMate API Phase 4 listening on ${port}`));
