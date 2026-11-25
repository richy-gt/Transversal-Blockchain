const solc=require('solc'),fs=require('fs');
const src=fs.readFileSync(__dirname+'/../contracts/AcuerdoExportacion.sol','utf8');
const out=JSON.parse(solc.compile(JSON.stringify({language:'Solidity',sources:{'AcuerdoExportacion.sol':{content:src}},
 settings:{evmVersion:'paris',optimizer:{enabled:true,runs:200},outputSelection:{'*':{'*':['abi','evm.bytecode.object']}}}})));
let err=false;(out.errors||[]).forEach(e=>{console.log(e.severity.toUpperCase(),e.formattedMessage);if(e.severity==='error')err=true});
if(err)process.exit(1);
const c=out.contracts['AcuerdoExportacion.sol'];
for(const n in c)fs.writeFileSync(__dirname+`/../build/${n}.json`,JSON.stringify({abi:c[n].abi,bytecode:'0x'+c[n].evm.bytecode.object}));
console.log('OK compilado:',Object.keys(c).join(', '));
