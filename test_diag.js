const { app, BrowserWindow } = require('electron');
const path = require('path');

app.whenReady().then(async () => {
  const win = new BrowserWindow({
    width: 1200, height: 800,
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'dist', 'preload.js'),
      sandbox: false,
      contextIsolation: true,
      nodeIntegration: false,
      webviewTag: true
    }
  });
  
  win.loadFile(path.join(__dirname, 'dist', 'browser.html'));
  
  win.webContents.on('did-finish-load', async () => {
    await new Promise(r => setTimeout(r, 4000));
    
    const result = await win.webContents.executeJavaScript(`
      (function() {
        var info = {};
        info.tabCount = document.querySelectorAll('.tab').length;
        info.webviewWraps = document.querySelectorAll('.webview-wrap').length;
        info.ntpVisible = document.getElementById('ntp')?.classList.contains('visible');
        info.agVisible = document.getElementById('antergetPage')?.classList.contains('visible');
        info.settingsVisible = document.getElementById('settingsPage')?.classList.contains('visible');
        
        // Check if any full-screen element blocks clicks
        var el = document.elementFromPoint(600, 400);
        info.elementAtCenter = el ? el.tagName + '#' + el.id + '.' + el.className : 'null';
        
        // Check toolbar
        var tbEl = document.elementFromPoint(600, 60);
        info.elementAtToolbar = tbEl ? tbEl.tagName + '#' + tbEl.id + '.' + tbEl.className : 'null';
        
        // Check tab area
        var tabEl = document.elementFromPoint(200, 20);
        info.elementAtTabArea = tabEl ? tabEl.tagName + '#' + tabEl.id + '.' + tabEl.className : 'null';
        
        // Check visibility of key elements
        var backBtn = document.getElementById('backBtn');
        info.backBtnDisplay = backBtn ? getComputedStyle(backBtn).display : 'N/A';
        info.backBtnVisibility = backBtn ? getComputedStyle(backBtn).visibility : 'N/A';
        info.backBtnDisabled = backBtn?.disabled;
        
        // Check content area visibility
        var content = document.getElementById('content');
        info.contentDisplay = content ? getComputedStyle(content).display : 'N/A';
        info.contentHeight = content ? content.getBoundingClientRect().height : 0;
        
        // Check for overlays
        var allEls = document.querySelectorAll('*');
        var overlays = [];
        for (var i = 0; i < allEls.length; i++) {
          var s = getComputedStyle(allEls[i]);
          if (s.position === 'fixed' && s.display !== 'none' && s.visibility !== 'hidden' && s.opacity !== '0') {
            var r = allEls[i].getBoundingClientRect();
            if (r.width > 100 && r.height > 100) {
              overlays.push(allEls[i].tagName + '#' + allEls[i].id + ' ' + s.zIndex);
            }
          }
        }
        info.potentialOverlays = overlays;
        
        return info;
      })()
    `);
    
    console.log(JSON.stringify(result, null, 2));
    app.quit();
  });
});
