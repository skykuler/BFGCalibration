// Runs the actual HTML extracted from the IPA in a DOM test environment.
// This is a DOM/bridge contract test, not an iOS or Bluetooth runtime test.
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM, VirtualConsole } = require('jsdom');
const html = fs.readFileSync(process.env.BFG_UI_HTML || path.join(__dirname,'../ios/BFGCalibration/Resources/bfg-calibration-flow.html'), 'utf8');
const checks = [];
const errors = [];
const vehicles = [{sn:'A1234567890123',paired:true}, {sn:'B1234567890123',paired:true}];
function check(name, passed, observed, kind='DOM') {
  checks.push({name, passed:!!passed, observed, kind});
}
function fresh(extra='') {
  const events = [];
  const timers = new Set();
  const vc = new VirtualConsole();
  vc.on('jsdomError', e => errors.push(e.message));
  const dom = new JSDOM(html.replace('</body>', extra + '</body>'), {
    runScripts:'dangerously', url:'https://bfg-audit.invalid/', virtualConsole:vc,
    beforeParse(w) {
      // jsdom does not implement layout-dependent innerText. This polyfill is
      // used only by the upstream suite's text-presence assertion.
      Object.defineProperty(w.HTMLElement.prototype, 'innerText', {
        get() {
          const copy=this.cloneNode(true);
          copy.querySelectorAll('script,style,template,[hidden]').forEach(n=>n.remove());
          return copy.textContent;
        }, configurable:true
      });
      w.BfgNative = {action:(a,v) => events.push([a,String(v ?? '')])};
      const set = w.setInterval.bind(w), clear = w.clearInterval.bind(w);
      w.setInterval = (fn,ms,...args) => {
        const id = set(fn,ms,...args); timers.add(id); return id;
      };
      w.clearInterval = id => { timers.delete(id); return clear(id); };
    }
  });
  const w=dom.window, d=w.document;
  return {dom,w,d,events,timers,
    update(o) { w.bfgNativeUpdate(JSON.stringify(o)); },
    go(s) { w.bfgNativeGo(s); },
    click(sel) {
      const e=d.querySelector(sel);
      if(!e) throw Error('Missing '+sel);
      e.click();
    },
    last(action) { return events.filter(x=>x[0]===action).at(-1)?.[1]; },
    close() { w.close(); }
  };
}
async function main() {
  const upstream = fresh(fs.readFileSync(path.join(__dirname,'check-ui-wiring.py'),'utf8').match(/PAGE_TEST = r"""([\s\S]*?)"""/)[1]);
  await new Promise(resolve => upstream.w.addEventListener('load',resolve,{once:true}));
  const previous = upstream.d.title.split('|').slice(1);
  for(const line of previous) check('Upstream: '+line.slice(5),line.startsWith('PASS '),line,'upstream DOM regression');
  upstream.close();

  let t=fresh();
  check('Idle page has no active polling interval',t.timers.size===0,t.timers.size);
  t.update({vehicleSn:vehicles[0].sn,vehicles,connected:true,credentialAvailable:true});
  t.go('vehicles');
  t.click('[data-action="select-vehicle"][data-index="1"]');
  t.go('connect-ready');
  check('Selecting vehicle B changes the current vehicle from A to B',
    t.d.body.textContent.includes(vehicles[1].sn),
    {selectionEvent:t.last('select-vehicle'),currentText:t.d.body.textContent.match(/[AB]1234567890123/g)});
  t.close();

  t=fresh();
  t.update({vehicles,vehicleSn:'',connected:false});
  t.go('pair-list');
  t.click('[data-action="pair-select"][data-index="1"]');
  check('Pairing page emits the chosen index',t.last('pair-select')==='1',t.last('pair-select'));
  t.click('[data-action="wake-confirm"]');
  t.click('[data-action="begin-pair"]');
  check('Pair request still contains the chosen index',t.last('begin-pair')==='1',t.last('begin-pair'));
  // This control proves the actual page reports and displays its selected
  // choice indices; native identity restoration is covered by the Swift tests.
  check('Pair progress displays chosen B',t.d.body.textContent.includes(vehicles[1].sn),t.d.body.textContent.includes(vehicles[1].sn));
  t.close();

  const gate={nonce:74,seconds:0,title:'Audit gate',intro:'test',critical:'test',acknowledgement:'test',action:'Continue'};
  t=fresh();
  t.update({screen:'write-progress',writeGate:gate});
  t.click('[data-action="write-gate-cancel"]');
  check('Cancelling a write gate exits the progress screen',
    !t.d.querySelector('[role="progressbar"]'),
    {cancelEvent:t.last('write-gate-cancel'),progressbarStillPresent:!!t.d.querySelector('[role="progressbar"]')});
  check('Cancelling gate clears its interval',t.timers.size===0,t.timers.size);
  t.close();

  t=fresh();
  t.update({screen:'write-progress',writeGate:gate});
  const box=t.d.querySelector('#write-gate-check');
  box.checked=true; box.dispatchEvent(new t.w.Event('change'));
  check('Gate enables confirmation only after acknowledgement',!t.d.querySelector('#write-gate-confirm').disabled,'checked gate');
  t.update({busyMessage:'Unrelated status'});
  check('Unrelated native status preserves the gate acknowledgement',
    t.d.querySelector('#write-gate-check').checked,t.d.querySelector('#write-gate-check').checked);
  t.close();

  t=fresh();
  t.update({screen:'post-write-check',result:'success',modal:'write-success',errorMessage:'Confirmed'});
  t.click('[data-action="close-modal"]');
  check('Closing write success shows a completed result instead of an active spinner',
    !t.d.querySelector('[role="progressbar"]'),
    {progressbarStillPresent:!!t.d.querySelector('[role="progressbar"]'),screen:t.last('screen')});
  t.close();

  t=fresh();
  t.update({vehicleSn:vehicles[0].sn,connected:true,credentialAvailable:true});
  // The exact identity-related keys clearLocalData() sends; it never clears
  // vehicleSn. This checks the UI consequence without running Swift.
  t.update({vehicles:[],connected:false,modal:'data-cleared'});
  t.click('[data-action="close-modal"]');
  t.go('home');
  check('Clear-data payload removes the paired-credential claim',
    !t.d.querySelector('#nb-screen').textContent.includes('已保存到系统钥匙串'),
    t.d.querySelector('#nb-screen').textContent.includes('已保存到系统钥匙串'),'DOM using native payload traced from source');
  t.close();

  t=fresh();
  t.update({vehicleSn:vehicles[0].sn,screen:'review',writeSupported:true,vehicleVoltage:60,vehicleCapacity:26,
    capacityByVoltage:{'48':[20,26,32],'60':[20,26,32],'72':[20,26,32]},availableCapacities:[20,26,32]});
  t.click('[data-action="write"]');
  t.click('[data-voltage="72"]');
  t.click('[data-capacity="32"]');
  t.update({busyMessage:'status update'});
  t.click('[data-action="confirm-write"]');
  t.click('[data-action="do-write"]');
  const req=JSON.parse(t.last('do-write'));
  check('Native status preserves selected voltage and capacity',req.voltage===72&&req.capacity===32,req);
  t.close();

  t=fresh();
  const screens=['home','vehicles','settings','pair-list','pair-ready','pair-progress','connect-ready',
    'connect-progress','write','write-progress','post-write-check','scan-progress','scan-result','review'];
  for(const name of screens) {
    t.go(name);
    check('Screen renders: '+name,!!t.d.querySelector('#nb-screen')?.textContent.trim(),t.d.querySelector('#nb-screen')?.textContent.trim().length);
  }
  t.go('settings');
  const beforeNodes=t.d.querySelectorAll('*').length;
  for(let i=0;i<150;i++) t.update({busyMessage:'Update '+i});
  check('Repeated updates do not accumulate live DOM nodes',t.d.querySelectorAll('*').length===beforeNodes,
    {beforeNodes,afterNodes:t.d.querySelectorAll('*').length,updates:150});
  check('Experimental write and probe entries are absent', !t.d.querySelector('[data-action="expert-mode"],[data-action="capacity-write"],[data-action="probe-registers"],[data-action="sweep-values"],[data-action="dashboard-probe"]'), 'original feature scope');
  check('Repeated updates leave no idle interval',t.timers.size===0,t.timers.size);
  t.close();
  check('No unhandled JavaScript errors in DOM suite',errors.length===0,errors);
  const report={environment:'Node.js '+process.version+' / jsdom '+require('jsdom/package.json').version,
    input:process.env.BFG_UI_HTML || 'Current bundled UI source',
    scope:'DOM behavior only; no WebKit, native Swift, BLE radio, iPhone CPU or memory measurements',
    passed:checks.filter(x=>x.passed).length,failed:checks.filter(x=>!x.passed).length,checks};
  fs.mkdirSync(process.env.BFG_TEST_OUTPUT || path.join(__dirname,'../build'),{recursive:true});
  fs.writeFileSync(path.join(process.env.BFG_TEST_OUTPUT || path.join(__dirname,'../build'),'ui-test-results.json'),JSON.stringify(report,null,2));
  console.log(JSON.stringify({passed:report.passed,failed:report.failed,failures:checks.filter(x=>!x.passed)},null,2));
  if(report.failed) process.exitCode=1;
}
main().catch(e=>{console.error(e);process.exitCode=1});
