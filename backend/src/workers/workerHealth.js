const http=require('http');
function createWorkerHealth(port,state){const server=http.createServer((req,res)=>{if(req.url!=='/health'){res.writeHead(404);return res.end();}res.setHeader('Content-Type','application/json');res.writeHead(state.connected?200:503);const body={status:state.connected?'healthy':'degraded',connected:state.connected,lastError:state.lastError||null};
 for(const key of ['processedCount','ignoredCount','errorCount','lastProcessedAt'])if(state[key]!==undefined)body[key]=state[key];res.end(JSON.stringify(body));});server.listen(port);return server;}
module.exports={createWorkerHealth};
