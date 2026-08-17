// ===== dotenvx GUI — Frontend Application =====

let state = {
  currentDir: null,
  files: [],
  activeFile: null,
  variables: [],
  recentProjects: []
};

let apiToken = null;

// DOM Elements
const els = {
  btnOpen: document.getElementById('btn-open-folder'),
  btnOpenManual: document.getElementById('btn-open-manual'),
  currentProject: document.getElementById('current-project'),
  recentList: document.getElementById('recent-list'),
  btnEncrypt: document.getElementById('btn-encrypt'),
  btnDecrypt: document.getElementById('btn-decrypt'),
  btnAddVar: document.getElementById('btn-add-var'),
  btnRun: document.getElementById('btn-run'),
  fileTabs: document.getElementById('file-tabs'),
  docHeader: document.getElementById('doc-header'),
  docName: document.getElementById('doc-name'),
  docSealUse: document.getElementById('doc-seal-use'),
  docSealState: document.getElementById('doc-seal-state'),
  docSealCount: document.getElementById('doc-seal-count'),
  varTable: document.getElementById('var-table'),
  varTbody: document.getElementById('var-tbody'),
  emptyState: document.getElementById('empty-state'),
  btnEmptyOpen: document.getElementById('btn-empty-open'),
  btnEmptyGuide: document.getElementById('btn-empty-guide'),
  outputPanel: document.getElementById('output-panel'),
  outputContent: document.getElementById('output-content'),
  toggleOutput: document.getElementById('toggle-output'),
  clearOutput: document.getElementById('clear-output'),

  folderDialog: document.getElementById('folder-dialog'),
  folderForm: document.getElementById('folder-form'),
  folderInput: document.getElementById('folder-input'),
  folderCancel: document.getElementById('folder-cancel'),

  addVarDialog: document.getElementById('add-var-dialog'),
  addVarForm: document.getElementById('add-var-form'),
  newKey: document.getElementById('new-key'),
  newValue: document.getElementById('new-value'),
  addVarCancel: document.getElementById('add-var-cancel'),

  runDialog: document.getElementById('run-dialog'),
  runForm: document.getElementById('run-form'),
  runCmdInput: document.getElementById('run-cmd-input'),
  runCancel: document.getElementById('run-cancel'),

  // Guide Elements
  guideDialog: document.getElementById('guide-dialog'),
  btnGuide: document.getElementById('btn-guide'),
  guideClose: document.getElementById('guide-close'),
  guideDone: document.getElementById('guide-done'),
  guideTabBtns: document.querySelectorAll('.guide-tab-btn'),
  guideSections: document.querySelectorAll('.guide-section'),

  btnLamp: document.getElementById('btn-lamp'),
  toastContainer: document.getElementById('toast-container')
};

// ---- Desk light ----
// Two views of the same desk. The button says what it will do, and the
// choice is remembered; the theme itself is applied in index.html's head.

const THEME_KEY = 'dotenvx-gui-theme';

function isLamplight() {
  return document.documentElement.getAttribute('data-theme') === 'lamplight';
}

function setTheme(lamplight) {
  if (lamplight) {
    document.documentElement.setAttribute('data-theme', 'lamplight');
  } else {
    document.documentElement.removeAttribute('data-theme');
  }
  els.btnLamp.textContent = lamplight ? 'Daylight' : 'Lamplight';
  try {
    localStorage.setItem(THEME_KEY, lamplight ? 'lamplight' : 'daylight');
  } catch (e) {
    // Private mode — the choice just will not survive a reload.
  }
}

// ---- API Layer ----

async function api(endpoint, method = 'GET', body = null) {
  const opts = {
    method,
    headers: { Accept: 'application/json' }
  };
  if (apiToken) opts.headers['X-Dotenvx-GUI-Token'] = apiToken;
  if (body) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }

  const res = await fetch(endpoint, opts);
  const json = await res.json();

  if (!json.success) {
    throw new Error(json.error || 'Unknown API error');
  }
  return json.data;
}

// ---- Session ----
// The launch token arrives in the URL fragment of the link the server prints.
// The server never hands it out over HTTP, because anything it would answer a
// browser with, it would equally answer any other local program with.

const TOKEN_KEY = 'dotenvx-gui-token';

function claimToken() {
  const fromHash = new URLSearchParams(location.hash.slice(1)).get('token');
  if (!fromHash) {
    // A reload has no fragment left to read; the tab kept its own copy.
    try {
      return sessionStorage.getItem(TOKEN_KEY);
    } catch (e) {
      return null;
    }
  }
  try {
    sessionStorage.setItem(TOKEN_KEY, fromHash);
  } catch (e) {
    // Private mode — the token just will not survive a reload.
  }
  // Keep it out of the address bar, bookmarks, and browser history.
  history.replaceState(null, '', location.pathname + location.search);
  return fromHash;
}

function failSession(message) {
  apiToken = null;
  try {
    sessionStorage.removeItem(TOKEN_KEY);
  } catch (e) {
    // Nothing stored to clear.
  }
  appendOutput(message, 'error');
  showToast('Local session unavailable', 'error');
  els.btnOpen.disabled = true;
  els.btnOpenManual.disabled = true;
  if (els.btnEmptyOpen) els.btnEmptyOpen.disabled = true;
}

// ---- Core Functions ----

async function init() {
  setTheme(isLamplight());
  setupEventListeners();
  apiToken = claimToken();
  if (!apiToken) {
    failSession('No launch token in this address. Open the exact link printed by dotenvx-gui.');
    return;
  }
  try {
    state.recentProjects = (await api('/api/recent')) || [];
    renderRecent();
    appendOutput('dotenvx GUI ready. Open a project folder to begin.', 'info');
  } catch (err) {
    failSession(`Could not establish a secure local session: ${err.message}`);
  }
}

async function loadRecent() {
  try {
    const projects = await api('/api/recent');
    state.recentProjects = projects || [];
    renderRecent();
  } catch (err) {
    // Not critical — recent file may not exist yet
    state.recentProjects = [];
    renderRecent();
  }
}

function renderRecent() {
  els.recentList.replaceChildren();
  if (state.recentProjects.length === 0) {
    const empty = document.createElement('li');
    empty.className = 'recent-empty';
    empty.textContent = 'No recent projects';
    els.recentList.appendChild(empty);
    return;
  }
  state.recentProjects.forEach(proj => {
    const li = document.createElement('li');
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'recent-project-btn';
    const name = document.createElement('span');
    name.className = 'recent-name';
    name.textContent = proj.name;
    const projectPath = document.createElement('span');
    projectPath.className = 'recent-path';
    projectPath.title = proj.path;
    projectPath.textContent = proj.path;
    button.append(name, projectPath);
    button.onclick = () => openFolder(proj.path);
    li.appendChild(button);
    els.recentList.appendChild(li);
  });
}

async function openFolder(dirPath) {
  try {
    appendOutput(`Opening folder: ${dirPath}`, 'info');

    const data = await api(`/api/files?dir=${encodeURIComponent(dirPath)}`);

    state.currentDir = dirPath;
    state.files = data.files || [];

    // Update sidebar
    const name = dirPath.split('/').filter(Boolean).pop() || dirPath;
    const projectName = document.createElement('strong');
    projectName.textContent = name;
    const lineBreak = document.createElement('br');
    const projectPath = document.createElement('span');
    projectPath.className = 'current-project-path';
    projectPath.textContent = dirPath;
    els.currentProject.replaceChildren(projectName, lineBreak, projectPath);

    // Show table, hide empty state
    els.emptyState.hidden = true;
    els.varTable.hidden = false;

    // Enable actions that match the available state
    const hasEnvironmentFile = state.files.length > 0;
    els.btnEncrypt.disabled = !hasEnvironmentFile;
    els.btnDecrypt.disabled = !hasEnvironmentFile;
    els.btnAddVar.disabled = !hasEnvironmentFile;
    els.btnRun.disabled = false;

    renderFileTabs();

    // Load first file automatically
    if (state.files.length > 0) {
      await loadFile(state.files[0]);
    } else {
      state.activeFile = null;
      state.variables = [];
      renderVariables();
      appendOutput('No .env files found in this directory.', 'info');
    }

    // Save to recent projects
    try {
      await api('/api/recent', 'POST', { path: dirPath });
      await loadRecent();
    } catch (e) {
      // Non-critical
    }

    showToast(`Opened: ${name}`, 'success');
  } catch (err) {
    showToast('Failed to open folder', 'error');
    appendOutput(`Error opening folder: ${err.message}`, 'error');
  }
}

async function loadFile(filename) {
  try {
    state.activeFile = filename;
    renderFileTabs();

    const filePath = state.currentDir + '/' + filename;
    const variables = await api(`/api/read?file=${encodeURIComponent(filePath)}`);

    state.variables = variables || [];
    renderVariables();
    appendOutput(`Loaded ${filename} (${state.variables.length} variables)`, 'info');
  } catch (err) {
    showToast('Failed to load file', 'error');
    appendOutput(`Error loading ${filename}: ${err.message}`, 'error');
  }
}

function renderFileTabs() {
  els.fileTabs.replaceChildren();
  state.files.forEach(file => {
    const tab = document.createElement('button');
    tab.type = 'button';
    tab.setAttribute('role', 'tab');
    tab.setAttribute('aria-selected', String(file === state.activeFile));
    tab.className = `tab${file === state.activeFile ? ' active' : ''}`;
    tab.textContent = file;
    tab.onclick = () => loadFile(file);
    els.fileTabs.appendChild(tab);
  });
}

// The seal states what is actually on disk: a file counts as encrypted only
// when every one of its values is. Never inferred from the presence of a key.
function renderDocHeader() {
  if (!state.activeFile) {
    els.docHeader.hidden = true;
    return;
  }

  const total = state.variables.length;
  const encrypted = state.variables.filter(v => v.encrypted).length;
  const sealed = total > 0 && encrypted === total;
  const wasSealed = els.docHeader.classList.contains('is-sealed');

  els.docHeader.hidden = false;
  els.docName.textContent = state.activeFile;
  els.docSealUse.setAttribute('href', sealed ? '#seal-whole' : '#seal-open');
  els.docHeader.classList.toggle('is-sealed', sealed);
  els.docHeader.classList.toggle('is-open', !sealed && total > 0);
  els.docHeader.classList.toggle('is-empty', total === 0);

  if (total === 0) {
    els.docSealState.textContent = 'Empty';
    els.docSealCount.textContent = 'No variables';
  } else {
    els.docSealState.textContent = sealed ? 'Encrypted' : 'Plaintext';
    els.docSealCount.textContent = `${encrypted} of ${total} values encrypted`;
  }

  // Press the seal onto the sheet the moment the file becomes fully encrypted.
  if (sealed && !wasSealed) {
    els.docHeader.classList.remove('just-sealed');
    void els.docHeader.offsetWidth;
    els.docHeader.classList.add('just-sealed');
  }
}

function renderVariables() {
  els.varTbody.replaceChildren();
  renderDocHeader();

  if (state.variables.length === 0) {
    const tr = document.createElement('tr');
    const td = document.createElement('td');
    td.colSpan = 4;
    td.className = 'table-empty';
    td.textContent = 'No variables in this file';
    tr.appendChild(td);
    els.varTbody.appendChild(tr);
    return;
  }

  state.variables.forEach(v => {
    const tr = document.createElement('tr');

    // Key cell
    const tdKey = document.createElement('td');
    tdKey.className = 'cell-key';
    tdKey.textContent = v.key;

    // Value cell
    const tdVal = document.createElement('td');
    tdVal.className = 'cell-value';

    const valDisplay = document.createElement('div');
    valDisplay.className = 'value-display';
    const spanVal = document.createElement('span');
    spanVal.textContent = '••••••••';

    const valInput = document.createElement('input');
    valInput.className = 'value-input';
    valInput.hidden = true;
    valInput.value = v.value;

    valDisplay.appendChild(spanVal);
    tdVal.appendChild(valDisplay);
    tdVal.appendChild(valInput);

    // Status cell
    const tdStatus = document.createElement('td');
    tdStatus.className = 'cell-status';
    const status = document.createElement('span');
    status.className = `badge ${v.encrypted ? 'encrypted' : 'plain'}`;
    status.textContent = v.encrypted ? 'Encrypted' : 'Unencrypted';
    tdStatus.appendChild(status);

    // Actions cell
    const tdActions = document.createElement('td');
    tdActions.className = 'cell-actions';

    // Reveal button
    const btnReveal = document.createElement('button');
    btnReveal.className = 'action-btn';
    btnReveal.type = 'button';
    btnReveal.textContent = 'Show';
    btnReveal.setAttribute('aria-label', `Show value for ${v.key}`);
    let isRevealed = false;
    btnReveal.onclick = () => {
      isRevealed = !isRevealed;
      spanVal.textContent = isRevealed ? v.value : '••••••••';
      btnReveal.textContent = isRevealed ? 'Hide' : 'Show';
      btnReveal.setAttribute('aria-label', `${isRevealed ? 'Hide' : 'Show'} value for ${v.key}`);
    };

    // Edit button
    const btnEdit = document.createElement('button');
    btnEdit.className = 'action-btn';
    btnEdit.type = 'button';
    btnEdit.textContent = 'Edit';
    btnEdit.setAttribute('aria-label', `Edit value for ${v.key}`);
    btnEdit.onclick = () => {
      valDisplay.hidden = true;
      valInput.hidden = false;
      valInput.value = v.value;
      valInput.focus();
    };

    const saveEdit = async () => {
      const newVal = valInput.value;
      valDisplay.hidden = false;
      valInput.hidden = true;
      if (newVal !== v.value) {
        await saveVariable(v.key, newVal);
      }
    };
    valInput.onblur = saveEdit;
    valInput.onkeydown = (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        saveEdit();
      }
      if (e.key === 'Escape') {
        valDisplay.hidden = false;
        valInput.hidden = true;
      }
    };

    // Delete button
    const btnDel = document.createElement('button');
    btnDel.className = 'action-btn delete';
    btnDel.type = 'button';
    btnDel.textContent = 'Delete';
    btnDel.setAttribute('aria-label', `Delete variable ${v.key}`);
    btnDel.onclick = async () => {
      if (confirm(`Delete variable "${v.key}"?`)) {
        await deleteVariable(v.key);
      }
    };

    tdActions.append(btnReveal, btnEdit, btnDel);
    tr.append(tdKey, tdVal, tdStatus, tdActions);
    els.varTbody.appendChild(tr);
  });
}

// ---- Variable Operations ----

async function saveVariable(key, value) {
  try {
    const filePath = state.currentDir + '/' + state.activeFile;
    await api('/api/set', 'POST', { file: filePath, key, value });

    appendOutput(`Set ${key} → saved`, 'success');
    showToast(`Saved ${key}`, 'success');

    await loadFile(state.activeFile);
  } catch (err) {
    showToast('Failed to save variable', 'error');
    appendOutput(`Error saving ${key}: ${err.message}`, 'error');
  }
}

async function addNewVariable(key, value) {
  try {
    const filePath = state.currentDir + '/' + state.activeFile;
    await api('/api/set', 'POST', { file: filePath, key, value });

    appendOutput(`Added ${key}`, 'success');
    showToast(`Added ${key}`, 'success');

    await loadFile(state.activeFile);
  } catch (err) {
    showToast('Failed to add variable', 'error');
    appendOutput(`Error adding ${key}: ${err.message}`, 'error');
  }
}

async function deleteVariable(key) {
  try {
    const filePath = state.currentDir + '/' + state.activeFile;
    await api('/api/unset', 'POST', { file: filePath, key });

    appendOutput(`Deleted ${key}`, 'success');
    showToast(`Deleted ${key}`, 'success');

    await loadFile(state.activeFile);
  } catch (err) {
    showToast('Failed to delete variable', 'error');
    appendOutput(`Error deleting ${key}: ${err.message}`, 'error');
  }
}

// ---- File and Process Actions ----

async function encryptFile() {
  if (!state.activeFile) return;
  try {
    const filePath = state.currentDir + '/' + state.activeFile;
    appendOutput(`Encrypting ${state.activeFile}…`, 'info');
    const result = await api('/api/encrypt', 'POST', { file: filePath });

    const output = (result.stdout || '') + (result.stderr || '');
    if (output.trim()) appendOutput(output.trim(), 'success');
    else appendOutput('Encryption complete.', 'success');

    showToast(`${state.activeFile} encrypted`, 'success');

    if (state.activeFile) await loadFile(state.activeFile);

    const data = await api(`/api/files?dir=${encodeURIComponent(state.currentDir)}`);
    state.files = data.files || [];
    renderFileTabs();
  } catch (err) {
    showToast('Encryption failed', 'error');
    appendOutput(`Encryption error: ${err.message}`, 'error');
  }
}

async function decryptFile() {
  if (!state.activeFile) return;

  const confirmed = confirm(
    `Decrypt ${state.activeFile}?\n\nThis writes its secret values to disk as plaintext until you encrypt the file again.`
  );
  if (!confirmed) return;

  try {
    const filePath = state.currentDir + '/' + state.activeFile;
    appendOutput(`Decrypting ${state.activeFile}…`, 'info');
    const result = await api('/api/decrypt', 'POST', { file: filePath });

    const output = (result.stdout || '') + (result.stderr || '');
    if (output.trim()) appendOutput(output.trim(), 'success');
    else appendOutput('Decryption complete.', 'success');

    showToast(`${state.activeFile} is now plaintext`, 'info');

    if (state.activeFile) await loadFile(state.activeFile);
  } catch (err) {
    showToast('Decryption failed', 'error');
    appendOutput(`Decryption error: ${err.message}`, 'error');
  }
}

async function runCommand(cmd) {
  try {
    setOutputExpanded(true);
    appendOutput(`> dotenvx run -- ${cmd}`, 'info');
    const result = await api('/api/run', 'POST', { dir: state.currentDir, cmd });

    const stdout = result.stdout || '';
    const stderr = result.stderr || '';
    if (stdout.trim()) appendOutput(stdout.trim(), 'success');
    if (stderr.trim()) appendOutput(stderr.trim(), 'error');
    if (!stdout.trim() && !stderr.trim()) appendOutput('Command completed (no output).', 'info');
  } catch (err) {
    appendOutput(`Command failed: ${err.message}`, 'error');
    showToast('Command failed', 'error');
  }
}

// ---- User Guide Navigation ----

function openGuide(tabName = 'start') {
  switchGuideTab(tabName);
  els.guideDialog.showModal();
}

function closeGuide() {
  els.guideDialog.close();
}

function switchGuideTab(tabName) {
  els.guideTabBtns.forEach(btn => {
    const isTarget = btn.getAttribute('data-guide-tab') === tabName;
    btn.classList.toggle('active', isTarget);
    btn.setAttribute('aria-selected', String(isTarget));
  });

  els.guideSections.forEach(sec => {
    const isTarget = sec.id === `guide-panel-${tabName}`;
    sec.classList.toggle('active', isTarget);
    sec.hidden = !isTarget;
  });
}

// ---- Utilities ----

function setOutputExpanded(expanded) {
  els.outputPanel.classList.toggle('is-collapsed', !expanded);
  els.toggleOutput.textContent = expanded ? 'Hide' : 'Show';
  els.toggleOutput.setAttribute('aria-expanded', String(expanded));
}

function appendOutput(text, type = 'info') {
  const div = document.createElement('div');
  div.className = `log-entry log-${type}`;
  const time = new Date().toLocaleTimeString([], { hour12: false });
  const timeLabel = document.createElement('span');
  timeLabel.className = 'log-time';
  timeLabel.textContent = `[${time}]`;
  const message = document.createElement('span');
  message.textContent = ` ${text}`;
  div.append(timeLabel, message);
  els.outputContent.appendChild(div);
  els.outputContent.scrollTop = els.outputContent.scrollHeight;
}

function showToast(msg, type = 'info') {
  const toast = document.createElement('div');
  toast.className = 'toast';

  const icons = { success: '✓', error: '✗', info: 'ℹ' };
  const icon = document.createElement('span');
  icon.className = `toast-icon ${type}`;
  icon.textContent = icons[type] || 'ℹ';
  const message = document.createElement('span');
  message.textContent = msg;
  toast.append(icon, message);
  els.toastContainer.appendChild(toast);

  setTimeout(() => {
    toast.classList.add('slide-out');
    toast.addEventListener('animationend', () => toast.remove());
  }, 3000);
}

// ---- Finder Folder Picker ----

async function pickFolderViaFinder() {
  try {
    appendOutput('Opening Finder folder picker…', 'info');
    const data = await api('/api/pick-folder', 'POST');
    if (data && data.path) {
      await openFolder(data.path);
    }
  } catch (err) {
    if (err.message === 'cancelled') {
      appendOutput('Folder selection cancelled.', 'info');
      return;
    }
    appendOutput('Finder picker unavailable, showing manual input.', 'info');
    els.folderInput.value = '';
    els.folderDialog.showModal();
    els.folderInput.focus();
  }
}

// ---- Event Listeners ----

function setupEventListeners() {
  // Open folder — Finder picker (primary)
  els.btnOpen.onclick = () => pickFolderViaFinder();
  if (els.btnEmptyOpen) els.btnEmptyOpen.onclick = () => pickFolderViaFinder();

  // Open folder — manual path (fallback)
  els.btnOpenManual.onclick = () => {
    els.folderInput.value = '';
    els.folderDialog.showModal();
    els.folderInput.focus();
  };
  els.folderCancel.onclick = () => els.folderDialog.close();
  els.folderForm.onsubmit = (e) => {
    e.preventDefault();
    const path = els.folderInput.value.trim();
    if (path) {
      openFolder(path);
      els.folderDialog.close();
    }
  };

  // Add variable
  els.btnAddVar.onclick = () => {
    els.newKey.value = '';
    els.newValue.value = '';
    els.addVarDialog.showModal();
    els.newKey.focus();
  };
  els.addVarCancel.onclick = () => els.addVarDialog.close();
  els.addVarForm.onsubmit = async (e) => {
    e.preventDefault();
    const key = els.newKey.value.trim();
    const value = els.newValue.value;
    if (key) {
      await addNewVariable(key, value);
      els.addVarDialog.close();
    }
  };

  // Run command
  els.btnRun.onclick = () => {
    els.runCmdInput.value = '';
    els.runDialog.showModal();
    els.runCmdInput.focus();
  };
  els.runCancel.onclick = () => els.runDialog.close();
  els.runForm.onsubmit = async (e) => {
    e.preventDefault();
    const cmd = els.runCmdInput.value.trim();
    if (cmd) {
      await runCommand(cmd);
      els.runDialog.close();
    }
  };

  // Encrypt / Decrypt selected file
  els.btnEncrypt.onclick = encryptFile;
  els.btnDecrypt.onclick = decryptFile;

  // Output
  els.toggleOutput.onclick = () => {
    setOutputExpanded(els.outputPanel.classList.contains('is-collapsed'));
  };
  els.clearOutput.onclick = () => {
    els.outputContent.replaceChildren();
  };

  // Desk light
  els.btnLamp.onclick = () => setTheme(!isLamplight());

  // Guide Dialog Triggers
  if (els.btnGuide) els.btnGuide.onclick = () => openGuide('start');
  if (els.btnEmptyGuide) els.btnEmptyGuide.onclick = () => openGuide('start');
  if (els.guideClose) els.guideClose.onclick = closeGuide;
  if (els.guideDone) els.guideDone.onclick = closeGuide;

  // Guide Tab Navigation
  els.guideTabBtns.forEach(btn => {
    btn.onclick = () => {
      const tabName = btn.getAttribute('data-guide-tab');
      switchGuideTab(tabName);
    };
    btn.onkeydown = (event) => {
      if (!['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
      event.preventDefault();
      const tabs = Array.from(els.guideTabBtns);
      const offset = event.key === 'ArrowRight' ? 1 : -1;
      const nextIndex = (tabs.indexOf(btn) + offset + tabs.length) % tabs.length;
      tabs[nextIndex].click();
      tabs[nextIndex].focus();
    };
  });

  // Keyboard Shortcuts
  document.addEventListener('keydown', (e) => {
    // If inside an input/textarea, ignore single key shortcuts
    const isInput = ['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName);

    if (e.metaKey || e.ctrlKey) {
      switch (e.key.toLowerCase()) {
        case 'o':
          e.preventDefault();
          pickFolderViaFinder();
          break;
        case 'e':
          if (!els.btnEncrypt.disabled) {
            e.preventDefault();
            encryptFile();
          }
          break;
        case 'd':
          if (!els.btnDecrypt.disabled) {
            e.preventDefault();
            decryptFile();
          }
          break;
        case '/':
          e.preventDefault();
          openGuide('start');
          break;
      }
    } else if (e.key === '?' && !isInput) {
      e.preventDefault();
      openGuide('start');
    }
  });
}

// ---- Initialize ----
init();
