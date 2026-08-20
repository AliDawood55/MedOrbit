const env=require('../src/config/env');
const db=require('../src/config/database');
const {rebuildAllInterests,rebuildUserInterest}=require('../src/services/recommendationProjection.service');

async function assertTarget(client){
 const identity=(await client.query(`SELECT current_database() database,system_identifier::text system_identifier FROM pg_control_system()`)).rows[0];
 if(env.app.environment==='test'){
  if(process.env.MEDORBIT_TEST_ISOLATION!=='docker'||env.database.host!=='postgres'||!identity.database.endsWith('_test'))throw new Error('Refusing recommendation rebuild outside isolated Docker test database');
 }else{
  if(process.env.REBUILD_USER_INTERESTS_CONFIRM!=='YES')throw new Error('REBUILD_USER_INTERESTS_CONFIRM=YES is required');
  if(identity.database!=='medorbit')throw new Error('Live recommendation rebuild requires database medorbit');
  if(!process.env.EXPECTED_POSTGRES_SYSTEM_IDENTIFIER||identity.system_identifier!==process.env.EXPECTED_POSTGRES_SYSTEM_IDENTIFIER)throw new Error('PostgreSQL system identifier mismatch');
 }
 return identity;
}

async function main(){
 const client=await db.getClient();
 try{
  const identity=await assertTarget(client);await client.query('BEGIN');await client.query(`SELECT pg_advisory_xact_lock(hashtext('medorbit-rebuild-user-interests-v1'))`);
  let result;
  if(process.env.REBUILD_USER_INTERESTS_USER_ID){const profiles=await rebuildUserInterest(client,process.env.REBUILD_USER_INTERESTS_USER_ID);result={usersWithAllowedEvents:1,profileRows:profiles.length};}
  else result=await rebuildAllInterests(client);
  await client.query('COMMIT');console.log(JSON.stringify({database:identity.database,systemIdentifier:identity.system_identifier,...result}));
 }catch(error){await client.query('ROLLBACK').catch(()=>{});throw error;}finally{client.release();await db.pool.end();}
}
main().catch(error=>{console.error(`Interest rebuild failed: ${String(error.message||error).slice(0,300)}`);process.exit(1);});
