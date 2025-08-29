#!/usr/bin/env node
"use strict";
const fs = require('fs');
const path = require('path');
const fetch = global.fetch || require('node-fetch');

const OUT_FILE = path.resolve(__dirname, '../../data/assets_inventory.json');

function safeLog(...args){ console.log(...args); }

async function fetchCloudflare(accountId, token){
  const base = `https://api.cloudflare.com/client/v4/accounts/${accountId}`;
  const headers = { Authorization: `Bearer ${token}`, 'Content-Type':'application/json' };
  const endpoints = {
    kv_namespaces: `${base}/storage/kv/namespaces`,
    d1_databases: `${base}/d1/database`,
    pages_projects: `${base}/pages/projects`,
    workers_scripts: `${base}/workers/scripts`,
    r2_buckets: `${base}/storage/r2/buckets`,
    pages_deployments: `${base}/pages/deployments`
  };

  const result = { ok: true, details: {} };
  for(const [k, url] of Object.entries(endpoints)){
    try{
      const res = await fetch(url, { headers });
      const json = await res.json();
      result.details[k] = json;
      if(!res.ok) result.ok = false;
    }catch(err){ result.details[k] = { error: String(err) }; result.ok = false; }
  }
  return result;
}

async function fetchProxmox(host, tokenHeader, user, pass){
  // tokenHeader should be like 'PVEAPIToken=USER!TOKENID=TOKEN' or null
  const result = { ok: true, details: {} };
  if(tokenHeader){
    try{
      const url = `https://${host}/api2/json/nodes`;
      const res = await fetch(url, { headers: { Authorization: tokenHeader }, rejectUnauthorized:false });
      const json = await res.json();
      result.details.nodes = json;
      if(!res.ok) result.ok=false;
    }catch(err){ result.details.nodes = { error: String(err) }; result.ok=false; }
    return result;
  }
  if(user && pass){
    try{
      // get ticket
      const loginUrl = `https://${host}/api2/json/access/ticket`;
      const form = new URLSearchParams(); form.append('username', user); form.append('password', pass);
      const res = await fetch(loginUrl, { method:'POST', body: form, headers: { 'Content-Type':'application/x-www-form-urlencoded' } , rejectUnauthorized:false });
      const json = await res.json();
      if(!res.ok){ result.ok=false; result.details.login = json; return result; }
      const ticket = json.data.ticket;
      const csrf = json.data.CSRFPreventionToken;
      // list nodes
      const nodesRes = await fetch(`https://${host}/api2/json/nodes`, { headers: { Cookie: `PVEAuthCookie=${ticket}`, CSRFPreventionToken: csrf }, rejectUnauthorized:false });
      result.details.nodes = await nodesRes.json();
      if(!nodesRes.ok) result.ok=false;
    }catch(err){ result.details.nodes = { error: String(err) }; result.ok=false; }
    return result;
  }
  result.details.note = 'No proxmox credentials provided';
  return result;
}

async function main(){
  const CF_TOKEN = process.env.CF_API_TOKEN || process.env.CLOUDFLARE_API_TOKEN || '';
  const CF_ACCOUNT = process.env.CF_ACCOUNT_ID || process.env.CLOUDFLARE_ACCOUNT_ID || '';
  const PROX_HOST = process.env.PROXMOX_HOST || process.env.PVE_HOST || '';
  const PROX_TOKEN = process.env.PROXMOX_API_TOKEN || process.env.PVE_API_TOKEN || '';
  const PROX_USER = process.env.PROXMOX_USER || '';
  const PROX_PASS = process.env.PROXMOX_PASS || '';

  const inventory = { ts: new Date().toISOString(), cloudflare: null, proxmox: null, notes: [] };

  if(CF_TOKEN && CF_ACCOUNT){
    safeLog('Querying Cloudflare...');
    inventory.cloudflare = await fetchCloudflare(CF_ACCOUNT, CF_TOKEN);
  }else{
    inventory.notes.push('Cloudflare credentials missing: set CF_API_TOKEN and CF_ACCOUNT_ID');
  }

  if(PROX_HOST){
    safeLog('Querying Proxmox...');
    inventory.proxmox = await fetchProxmox(PROX_HOST, PROX_TOKEN ? `PVEAPIToken=${PROX_TOKEN}` : null, PROX_USER, PROX_PASS);
  }else{
    inventory.notes.push('Proxmox host missing: set PROXMOX_HOST or PVE_HOST');
  }

  // write output directory
  try{
    fs.mkdirSync(path.dirname(OUT_FILE), { recursive: true });
    fs.writeFileSync(OUT_FILE, JSON.stringify(inventory, null, 2), 'utf8');
    safeLog('Inventory written to', OUT_FILE);
  }catch(err){ safeLog('Failed to write inventory:', err); process.exitCode=2; }

  console.log(JSON.stringify(inventory, null, 2));
}

main().catch(err=>{ console.error(err); process.exit(1); });
