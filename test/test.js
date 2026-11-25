const ganache=require('ganache'),{ethers}=require('ethers'),fs=require('fs'),assert=require('assert');
const load=n=>JSON.parse(fs.readFileSync(__dirname+`/../build/${n}.json`));
const log=[];const L=(s)=>{console.log(s);log.push(s)};
const E=['Creado','Firmado','Financiado','EnTransito','Entregado','Pagado','EnDisputa','Reembolsado','Cancelado'];
let RAW;
async function rv(c,m,args,msg){const t=await c[m].populateTransaction(...args);
 try{await RAW.request({method:'eth_call',params:[{from:c.runner.address,to:t.to,data:t.data},'latest']})}
 catch(e){assert(String(e.message).includes(msg),`esperaba "${msg}", obtuvo: ${e.message}`);return}
 assert.fail('debio revertir: '+msg)}
async function expectRevert(p,msg){try{await (await p).wait();}catch(e){assert(String(e.message+e.reason).includes(msg),`esperaba "${msg}", obtuvo: ${e.reason||e.message}`);return}assert.fail('debio revertir: '+msg)}
async function escenario(nombre,fn){
  RAW=ganache.provider({logging:{quiet:true},chain:{vmErrorsOnRPCResponse:true},wallet:{totalAccounts:8,deterministic:true}});
  const prov=new ethers.BrowserProvider(RAW);
  const s=[];for(let i=0;i<8;i++)s.push(await prov.getSigner(i));
  const [dep,exp,imp,tra,ora,a1,a2,a3]=s;
  const T=load('PagoToken'),A=load('AcuerdoExportacion');
  const token=await new ethers.ContractFactory(T.abi,T.bytecode,dep).deploy();await token.waitForDeployment();
  const precio=12_500n*10n**6n;
  await (await token.mint(imp.address,precio)).wait();
  const limite=(await prov.getBlock('latest')).timestamp+14*86400;
  const ac=await new ethers.ContractFactory(A.abi,A.bytecode,dep).deploy(await token.getAddress(),exp.address,imp.address,tra.address,ora.address,[a1.address,a2.address,a3.address],'Vino Carmenere Reserva 2023 (cajas x12)',500,precio,80,limite);
  await ac.waitForDeployment();
  const st=async()=>E[Number(await ac.estado())];
  const h=await ac.hashTerminos();
  L(`\n=== ${nombre} ===`);
  L(`Contrato: ${await ac.getAddress()}  | hashTerminos: ${h.slice(0,18)}...`);
  const tx=async(label,p)=>{const r=await (await p).wait();L(`  tx ${r.hash.slice(0,12)}...  ${label.padEnd(38)} gas=${r.gasUsed}  -> estado: ${await st()}`);return r};
  await fn({prov,ac,token,exp,imp,tra,ora,a1,a2,a3,precio,h,tx,st,limite});
}
(async()=>{
 await escenario('1. Flujo feliz (cadena de frio cumplida)',async c=>{
  const {ac,token,exp,imp,tra,ora,precio,h,tx,st}=c;
  await rv(ac.connect(c.a1),'firmar',[h],'Solo las partes');
  await rv(ac.connect(exp),'firmar',[ethers.ZeroHash],'El hash no coincide');
  await tx('Exportador firma (hash de terminos)',ac.connect(exp).firmar(h));
  await rv(ac.connect(exp),'firmar',[h],'Ya firmo');
  await tx('Importador firma -> acuerdo inicia',ac.connect(imp).firmar(h));
  assert.equal(await st(),'Firmado');
  await tx('Importador: approve token',token.connect(imp).approve(await ac.getAddress(),precio));
  await rv(ac.connect(exp),'depositarPago',[],'Solo el importador');
  await tx('Importador deposita pago en garantia',ac.connect(imp).depositarPago());
  assert.equal(await ac.saldoEnGarantia(),precio);
  await tx('Transportista inicia transito',ac.connect(tra).iniciarTransito());
  await rv(ac.connect(imp),'reportarTemperatura',[50],'Solo el oraculo');
  await tx('Oraculo: lectura 5,0 C',ac.connect(ora).reportarTemperatura(50));
  await tx('Oraculo: lectura 7,2 C',ac.connect(ora).reportarTemperatura(72));
  assert.equal(await ac.incumplimientoTermico(),false);
  await tx('Transportista registra entrega',ac.connect(tra).registrarEntrega());
  await tx('Importador confirma recepcion -> paga',ac.connect(imp).confirmarRecepcion());
  assert.equal(await st(),'Pagado');assert.equal(await token.balanceOf(exp.address),precio);assert.equal(await ac.saldoEnGarantia(),0n);
  L('  OK: exportador recibio 12.500 USDm, escrow en 0');
 });
 await escenario('2. Incumplimiento termico -> disputa DAO -> reembolso',async c=>{
  const {ac,token,exp,imp,tra,ora,a1,a2,a3,precio,h,tx,st}=c;
  await ac.connect(exp).firmar(h);await ac.connect(imp).firmar(h);
  await token.connect(imp).approve(await ac.getAddress(),precio);await ac.connect(imp).depositarPago();await ac.connect(tra).iniciarTransito();
  await tx('Oraculo: lectura 11,5 C (excede 8,0)',ac.connect(ora).reportarTemperatura(115));
  assert.equal(await ac.incumplimientoTermico(),true);
  await tx('Transportista registra entrega',ac.connect(tra).registrarEntrega());
  await rv(ac.connect(imp),'confirmarRecepcion',[],'incumplimiento termico');
  await rv(ac.connect(exp),'reclamarPago',[],'incumplimiento termico');
  await tx('Importador abre disputa',ac.connect(imp).abrirDisputa());
  await rv(ac.connect(imp),'votar',[true],'Solo arbitros');
  await tx('Arbitro 1 vota a favor importador',ac.connect(a1).votar(true));
  await rv(ac.connect(a1),'votar',[true],'Ya voto');
  await tx('Arbitro 2 vota a favor importador',ac.connect(a2).votar(true));
  assert.equal(await st(),'Reembolsado');assert.equal(await token.balanceOf(imp.address),precio);
  L('  OK: mayoria 2/3 ejecuto reembolso automaticamente');
 });
 await escenario('3. Disputa resuelta a favor del exportador',async c=>{
  const {ac,token,exp,imp,tra,a1,a2,a3,precio,h,tx,st}=c;
  await ac.connect(exp).firmar(h);await ac.connect(imp).firmar(h);
  await token.connect(imp).approve(await ac.getAddress(),precio);await ac.connect(imp).depositarPago();await ac.connect(tra).iniciarTransito();await ac.connect(tra).registrarEntrega();
  await tx('Exportador abre disputa',ac.connect(exp).abrirDisputa());
  await tx('Arbitro 1 vota a favor exportador',ac.connect(a1).votar(false));
  await tx('Arbitro 2 vota a favor importador',ac.connect(a2).votar(true));
  await tx('Arbitro 3 vota a favor exportador -> paga',ac.connect(a3).votar(false));
  assert.equal(await st(),'Pagado');assert.equal(await token.balanceOf(exp.address),precio);
 });
 await escenario('4. Plazos: reclamar pago y reembolso por demora',async c=>{
  const {prov,ac,token,exp,imp,tra,precio,h,tx,st}=c;
  await ac.connect(exp).firmar(h);await ac.connect(imp).firmar(h);
  await token.connect(imp).approve(await ac.getAddress(),precio);await ac.connect(imp).depositarPago();await ac.connect(tra).iniciarTransito();
  await rv(ac.connect(imp),'reclamarReembolso',[],'Aun hay plazo');
  await prov.send('evm_increaseTime',[15*86400]);await prov.send('evm_mine',[]);
  await tx('Importador reclama reembolso (plazo vencido)',ac.connect(imp).reclamarReembolso());
  assert.equal(await st(),'Reembolsado');
 });
 await escenario('5. Silencio del importador: exportador cobra a los 3 dias',async c=>{
  const {prov,ac,token,exp,imp,tra,precio,h,tx,st}=c;
  await ac.connect(exp).firmar(h);await ac.connect(imp).firmar(h);
  await token.connect(imp).approve(await ac.getAddress(),precio);await ac.connect(imp).depositarPago();await ac.connect(tra).iniciarTransito();await ac.connect(tra).registrarEntrega();
  await rv(ac.connect(exp),'reclamarPago',[],'Plazo de confirmacion vigente');
  await prov.send('evm_increaseTime',[3*86400+5]);await prov.send('evm_mine',[]);
  await tx('Exportador reclama pago',ac.connect(exp).reclamarPago());
  assert.equal(await st(),'Pagado');
 });
 await escenario('6. Cancelacion antes de financiar y validaciones',async c=>{
  const {ac,exp,imp,tra,h,tx,st}=c;
  await rv(ac.connect(imp),'depositarPago',[],'Estado invalido');
  await tx('Exportador firma',ac.connect(exp).firmar(h));
  await tx('Importador cancela',ac.connect(imp).cancelar());
  assert.equal(await st(),'Cancelado');
 });
 L('\nTODAS LAS PRUEBAS PASARON (6 escenarios)');
 fs.writeFileSync(__dirname+'/../evidencia_pruebas.txt',log.join('\n'));
 process.exit(0);
})().catch(e=>{console.error('FALLO',e);process.exit(1)});
