const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function buildEnvelope(row,producer='medorbit-api'){
 return{eventId:row.id,eventType:row.event_type,eventVersion:Number(row.event_version),occurredAt:new Date(row.created_at).toISOString(),
  aggregateType:row.aggregate_type,aggregateId:row.aggregate_id||null,producer,payload:row.payload};
}
function validateEnvelope(value){
 if(!value||typeof value!=='object'||Array.isArray(value))throw new Error('Malformed event envelope');
 if(!UUID.test(String(value.eventId||'')))throw new Error('Malformed event id');
 if(!/^[a-z][a-z0-9_.-]{2,149}$/.test(String(value.eventType||'')))throw new Error('Malformed event type');
 if(value.eventVersion!==1)throw new Error('Unsupported event version');
 if(!value.occurredAt||Number.isNaN(Date.parse(value.occurredAt)))throw new Error('Malformed occurredAt');
 if(!value.aggregateType||typeof value.aggregateType!=='string')throw new Error('Malformed aggregate type');
 if(!value.payload||typeof value.payload!=='object'||Array.isArray(value.payload))throw new Error('Malformed event payload');
 return value;
}
module.exports={buildEnvelope,validateEnvelope};
