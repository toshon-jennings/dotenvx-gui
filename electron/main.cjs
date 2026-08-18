const { once } = require('node:events');
const { app, BrowserWindow } = require('electron');
const { startServer } = require('../server');

let mainWindow = null;
let localServer = null;

async function getLocalUrl() {
  if (!localServer) {
    localServer = startServer({ port: 0 }).server;
    await once(localServer, 'listening');
  }

  const address = localServer.address();
  return `http://127.0.0.1:${address.port}`;
}

async function createWindow() {
  const localUrl = await getLocalUrl();

  mainWindow = new BrowserWindow({
    title: 'dotenvx GUI',
    width: 1100,
    height: 750,
    minWidth: 850,
    minHeight: 550,
    show: false,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });

  mainWindow.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (url !== localUrl && !url.startsWith(`${localUrl}/`)) event.preventDefault();
  });
  mainWindow.once('ready-to-show', () => mainWindow.show());
  mainWindow.on('closed', () => {
    mainWindow = null;
  });

  await mainWindow.loadURL(localUrl);
}

app.whenReady().then(createWindow).catch(error => {
  console.error(error);
  app.quit();
});

app.on('activate', () => {
  if (!mainWindow) createWindow().catch(console.error);
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('before-quit', () => {
  if (localServer?.listening) localServer.close();
});
