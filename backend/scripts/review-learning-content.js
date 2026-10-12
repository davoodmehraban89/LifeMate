// This command does not contact video providers, AI, email or live services.
import fs from 'node:fs/promises';
import pg from 'pg';
import {localContentReviewConnection,inspectLearningContent,reviewLearningContent,ContentPublicationError} from '../src/content_publication.js';

const [action,first,second,...extra]=process.argv.slice(2);
let client;
async function operationFile(filename) {
  const maximum=1024*1024,file=await fs.open(filename,'r');
  try {
    const details=await file.stat();
    if(!details.isFile()||details.size>maximum) throw new ContentPublicationError('invalid_operation_file');
    const buffer=Buffer.alloc(maximum+1);let length=0;
    while(length<buffer.length) {
      const {bytesRead}=await file.read(buffer,length,buffer.length-length,null);
      if(!bytesRead) break;length+=bytesRead;
    }
    if(length>maximum) throw new ContentPublicationError('invalid_operation_file');
    return JSON.parse(buffer.subarray(0,length).toString('utf8'));
  } finally {await file.close();}
}
try {
  if(extra.length||!['inspect','dry-run','apply'].includes(action)||!first||
    (action==='inspect'?!second:second!==undefined)) throw new ContentPublicationError('invalid_command');
  const connection=localContentReviewConnection(process.env);
  const body=action==='inspect'?null:await operationFile(first);
  client=new pg.Client({connectionString:connection});await client.connect();
  const result=action==='inspect'?await inspectLearningContent(client,first,second):
    await reviewLearningContent(client,body,{apply:action==='apply'});
  console.log(JSON.stringify(result));
} catch(error) {
  // Do not print database URLs, raw driver errors or the chosen JSON payload.
  console.error(JSON.stringify({status:'rejected',code:error instanceof ContentPublicationError?error.code:'content_operation_rejected'}));
  process.exitCode=1;
} finally {if(client) await client.end().catch(()=>{});}
