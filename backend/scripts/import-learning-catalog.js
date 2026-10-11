import fs from 'node:fs/promises';
import pg from 'pg';
import { importLearningCatalog,validateDataset } from '../src/learning_catalog.js';
const args=process.argv.slice(2),files=[];let check=false;
for(let i=0;i<args.length;i++){if(args[i]==='--check')check=true;else if(args[i]==='--file'&&args[i+1])files.push(args[++i]);else throw new Error('usage: import-learning-catalog.js [--check] [--file path]');}
if(!files.length)files.push(new URL('../content/iran-primary-aparat.json',import.meta.url),new URL('../content/iran-secondary-aparat.json',import.meta.url));
const data=await Promise.all(files.map(async file=>JSON.parse(await fs.readFile(file,'utf8'))));
if(check){console.log(JSON.stringify({status:'validated',datasets:data.map(validateDataset)}));}else{const pool=new pg.Pool({connectionString:process.env.DATABASE_URL});try{console.log(JSON.stringify({status:'imported',...await importLearningCatalog(pool,data),publicationStatus:'draft'}));}finally{await pool.end();}}
