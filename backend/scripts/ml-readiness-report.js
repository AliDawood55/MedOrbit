const env=require('../src/config/env');
const db=require('../src/config/database');
const {collectMlReadiness}=require('../src/services/mlReadiness.service');

function assertConfiguredTarget(){
 if(env.app.environment==='test'){
  if(process.env.MEDORBIT_TEST_ISOLATION!=='docker'||env.database.host!=='postgres'||!env.database.name.endsWith('_test'))throw new Error('Refusing ML readiness test report outside isolated Docker test database');
  return;
 }
 if(env.database.host!=='postgres'||env.database.name!=='medorbit')throw new Error('Live ML readiness report requires Docker database medorbit');
 if(!process.env.ML_READINESS_EXPECTED_SYSTEM_IDENTIFIER)throw new Error('ML_READINESS_EXPECTED_SYSTEM_IDENTIFIER is required');
}

(async()=>{try{
 assertConfiguredTarget();const report=await collectMlReadiness();
 if(env.app.environment!=='test'&&report.systemIdentifier!==process.env.ML_READINESS_EXPECTED_SYSTEM_IDENTIFIER)throw new Error('PostgreSQL system identifier mismatch');
 const {systemIdentifier,...safeReport}=report;console.log(JSON.stringify(safeReport));
 }catch(error){console.error(`ML readiness report failed: ${String(error.message||error).slice(0,240)}`);process.exitCode=1;}finally{await db.pool.end();}})();
