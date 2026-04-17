const app = document.getElementById('app');
const feedback = document.getElementById('feedback');
const tierValue = document.getElementById('tierValue');
const heatValue = document.getElementById('heatValue');
const timeValue = document.getElementById('timeValue');
const modeDescription = document.getElementById('modeDescription');
const sourceDescription = document.getElementById('sourceDescription');
const traceBar = document.getElementById('traceBar');
const traceValue = document.getElementById('traceValue');
const stealthBar = document.getElementById('stealthBar');
const stealthValue = document.getElementById('stealthValue');
const nodeBar = document.getElementById('nodeBar');
const nodeValue = document.getElementById('nodeValue');
const tierPicker = document.getElementById('tierPicker');
const sourcePicker = document.getElementById('sourcePicker');
const cardSelect = document.getElementById('cardSelect');

const stages = {
  sequence: document.getElementById('stageSequence'),
  wires: document.getElementById('stageWires'),
  code: document.getElementById('stageCode')
};

const sequenceGrid = document.getElementById('sequenceGrid');
const replayBtn = document.getElementById('replayBtn');
const wireRack = document.getElementById('wireRack');
const wireHint = document.getElementById('wireHint');
const codeInput = document.getElementById('codeInput');
const guessBtn = document.getElementById('guessBtn');
const guessLog = document.getElementById('guessLog');

let game = null;
let timerTick = null;

const tierDescriptions = {
  1: 'Ghost: easier puzzle profile, lowest payout multiplier.',
  2: 'Balanced: medium difficulty and improved reward scaling.',
  3: 'Overclock: maximum trace pressure, highest payout multiplier.'
};

const sourceDescriptions = {
  atm: 'ATM Bus: direct intrusion against the ATM host bank.',
  card: 'Stolen Card: swipe a stolen card, pull login metadata, and siphon account funds.'
};

const post = (event, data = {}) => {
  fetch(`https://${GetParentResourceName()}/${event}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  });
};

const setStage = (name) => {
  Object.values(stages).forEach(stage => stage.classList.remove('active'));
  stages[name].classList.add('active');
};

const updateTelemetry = () => {
  const trace = Math.max(0, Math.min(100, game.trace));
  const stealth = Math.max(0, 100 - trace);
  const nodes = game.stageIndex;

  traceBar.style.width = `${trace}%`;
  traceValue.textContent = `${trace}%`;

  stealthBar.style.width = `${stealth}%`;
  stealthValue.textContent = `${stealth}%`;

  nodeBar.style.width = `${(nodes / 3) * 100}%`;
  nodeValue.textContent = `${nodes}/3`;
};

const addTrace = (amount) => {
  game.trace = Math.max(0, Math.min(100, game.trace + amount));
  updateTelemetry();

  if (game.trace >= 100) {
    fail('Trace reached 100%. Bank ICE fully locked your session.');
  }
};

const getSelectedCard = () => game.cards.find(card => card.cardId === game.selectedCardId);

const validateSourceSelection = () => {
  if (game.sourceMode !== 'card') return true;

  if (!game.cards.length) {
    feedback.textContent = 'No stolen cards available. Switch source mode or steal a card first.';
    return false;
  }

  if (!game.selectedCardId) {
    feedback.textContent = 'Select a stolen card before running intrusion.';
    return false;
  }

  return true;
};

const fail = (reason) => {
  feedback.textContent = reason;
  clearInterval(timerTick);
  post('finishHack', {
    success: false,
    mode: game.sourceMode,
    cardId: game.selectedCardId,
    tier: game.tier,
    trace: game.trace,
    stageReached: game.stageIndex,
    reason: 'failed'
  });
};

const win = () => {
  feedback.textContent = game.sourceMode === 'card'
    ? 'Card auth chain cracked. Credentials exfiltrated and transfer staged.'
    : 'Payload injected. QS banking route accepted.';

  clearInterval(timerTick);

  post('finishHack', {
    success: true,
    mode: game.sourceMode,
    cardId: game.selectedCardId,
    tier: game.tier,
    trace: game.trace,
    stageReached: 3,
    reason: 'success'
  });
};

const buildSequence = () => {
  sequenceGrid.innerHTML = '';

  for (let i = 0; i < 9; i++) {
    const btn = document.createElement('button');
    btn.dataset.index = i;

    btn.addEventListener('click', () => {
      if (game.locked) return;

      const expected = game.sequence[game.sequenceInput.length];
      if (+btn.dataset.index !== expected) {
        addTrace(18);
        fail('Pattern mismatch. Intrusion monitor escalated.');
        return;
      }

      btn.classList.add('flash');
      setTimeout(() => btn.classList.remove('flash'), 180);
      game.sequenceInput.push(expected);

      if (game.sequenceInput.length === game.sequence.length) {
        game.stageIndex = 1;
        addTrace(5 + game.tier);
        feedback.textContent = 'Node 1 compromised. Entering circuit bypass.';
        setStage('wires');
      }
    });

    sequenceGrid.appendChild(btn);
  }
};

const replaySequence = async () => {
  game.locked = true;
  const nodes = [...sequenceGrid.querySelectorAll('button')];

  for (const i of game.sequence) {
    const node = nodes[i];
    node.classList.add('flash');
    await new Promise(r => setTimeout(r, 420));
    node.classList.remove('flash');
    await new Promise(r => setTimeout(r, 120));
  }

  game.locked = false;
};

const buildWires = () => {
  wireRack.innerHTML = '';
  wireHint.textContent = `Cut order starts with ${game.wireOrder[0].toUpperCase()}.`;

  game.wires.forEach(name => {
    const wire = document.createElement('button');
    wire.className = 'wire';
    wire.textContent = name;
    wire.style.background = `linear-gradient(145deg, ${game.wireColors[name]}, #0d1a2c)`;

    wire.addEventListener('click', () => {
      if (wire.classList.contains('cut')) return;

      const expected = game.wireOrder[game.wireProgress];
      if (name !== expected) {
        addTrace(20);
        fail(`${name.toUpperCase()} was a decoy wire. IDS alerted.`);
        return;
      }

      wire.classList.add('cut');
      game.wireProgress += 1;
      addTrace(4 + game.tier);

      if (game.wireProgress === game.wireOrder.length) {
        game.stageIndex = 2;
        feedback.textContent = 'Node 2 bypassed. Launching cipher shell.';
        setStage('code');
        return;
      }

      wireHint.textContent = `Clean cut. Next: ${game.wireOrder[game.wireProgress].toUpperCase()}`;
    });

    wireRack.appendChild(wire);
  });
};

const buildCode = () => {
  guessLog.innerHTML = '';
  codeInput.value = '';
  codeInput.focus();
};

const pushGuessLog = (txt) => {
  const item = document.createElement('div');
  item.className = 'log-item';
  item.textContent = txt;
  guessLog.prepend(item);
};

const scoreGuess = (guess, answer) => {
  let exact = 0;
  let partial = 0;
  const answerUsed = [false, false, false, false];
  const guessUsed = [false, false, false, false];

  for (let i = 0; i < 4; i++) {
    if (guess[i] === answer[i]) {
      exact += 1;
      answerUsed[i] = true;
      guessUsed[i] = true;
    }
  }

  for (let i = 0; i < 4; i++) {
    if (guessUsed[i]) continue;
    for (let j = 0; j < 4; j++) {
      if (answerUsed[j]) continue;
      if (guess[i] === answer[j]) {
        partial += 1;
        answerUsed[j] = true;
        break;
      }
    }
  }

  return { exact, partial };
};

const submitGuess = () => {
  const raw = codeInput.value.trim();
  if (!/^\d{4}$/.test(raw)) {
    feedback.textContent = 'Cipher requires exactly 4 digits.';
    return;
  }

  game.guesses += 1;

  if (raw === game.answer) {
    game.stageIndex = 3;
    addTrace(6 + game.tier);
    win();
    return;
  }

  const result = scoreGuess(raw, game.answer);
  pushGuessLog(`#${game.guesses}: ${raw} | exact ${result.exact} | nearby ${result.partial}`);

  addTrace(8 + game.tier * 2);

  if (game.guesses >= game.maxGuesses) {
    fail('Bruteforce limit exceeded. Session burned.');
    return;
  }

  feedback.textContent = `Miss. ${game.maxGuesses - game.guesses} attempts left.`;
  codeInput.value = '';
  codeInput.focus();
};

const setTier = (tier) => {
  game.tier = tier;
  tierValue.textContent = String(tier);

  tierPicker.querySelectorAll('.tier').forEach(node => {
    node.classList.toggle('active', Number(node.dataset.tier) === tier);
  });

  modeDescription.textContent = tierDescriptions[tier];
};

const setSourceMode = (sourceMode) => {
  game.sourceMode = sourceMode;

  sourcePicker.querySelectorAll('.tier').forEach(node => {
    node.classList.toggle('active', node.dataset.source === sourceMode);
  });

  sourceDescription.textContent = sourceDescriptions[sourceMode] || sourceDescriptions.atm;

  const showCardSelect = sourceMode === 'card';
  cardSelect.classList.toggle('hidden', !showCardSelect);

  if (showCardSelect && !game.cards.length) {
    sourceDescription.textContent = 'No stolen cards detected. Use /stealcard near a player first.';
  }

  if (showCardSelect && !game.selectedCardId && game.cards[0]) {
    game.selectedCardId = game.cards[0].cardId;
  }
};

const rebuildCardSelect = () => {
  cardSelect.innerHTML = '';

  if (!game.cards.length) {
    const opt = document.createElement('option');
    opt.value = '';
    opt.textContent = 'No stolen cards available';
    cardSelect.appendChild(opt);
    return;
  }

  game.cards.forEach(card => {
    const opt = document.createElement('option');
    opt.value = card.cardId;
    opt.textContent = `${card.holder} | ${card.masked} | ${card.bankName}`;
    cardSelect.appendChild(opt);
  });

  const selected = game.cards.find(card => card.cardId === game.selectedCardId) || game.cards[0];
  game.selectedCardId = selected.cardId;
  cardSelect.value = selected.cardId;
};

const regenerateByTier = (tier) => {
  const seqLen = tier === 1 ? 4 : tier === 2 ? 5 : 6;
  const orderLen = tier === 3 ? 4 : 3;
  game.maxGuesses = tier === 1 ? 8 : tier === 2 ? 6 : 5;
  game.sequenceInput = [];
  game.wireProgress = 0;
  game.guesses = 0;
  game.sequence = Array.from({ length: seqLen }, () => Math.floor(Math.random() * 9));
  game.wireOrder = game.wires.slice().sort(() => 0.5 - Math.random()).slice(0, orderLen);
  game.answer = String(Math.floor(Math.random() * 10000)).padStart(4, '0');
};

const startGame = (payload, maxDuration) => {
  game = {
    tier: 1,
    sourceMode: 'atm',
    selectedCardId: null,
    cards: payload?.stolenCards || [],
    heat: payload?.heat || 0,
    timeLeft: maxDuration || 95,
    sequenceInput: [],
    wires: ['amber', 'cyan', 'violet', 'lime', 'ruby'],
    wireColors: {
      amber: '#ffc14f',
      cyan: '#50e3ff',
      violet: '#9f7fff',
      lime: '#b2ff61',
      ruby: '#ff5e78'
    },
    wireProgress: 0,
    guesses: 0,
    maxGuesses: 8,
    trace: 0,
    stageIndex: 0,
    locked: false
  };

  setTier(1);
  regenerateByTier(1);
  rebuildCardSelect();
  setSourceMode('atm');

  heatValue.textContent = String(game.heat);
  timeValue.textContent = String(game.timeLeft);

  buildSequence();
  buildWires();
  buildCode();
  setStage('sequence');
  feedback.textContent = 'Laptop linked to ATM bus. Configure profile and start pattern sync.';
  updateTelemetry();

  replaySequence();

  clearInterval(timerTick);
  timerTick = setInterval(() => {
    game.timeLeft -= 1;
    timeValue.textContent = String(game.timeLeft);

    if (game.timeLeft <= 0) {
      fail('Time expired. Security daemon won.');
      return;
    }

    addTrace(1 + Math.floor(game.heat / 2));
  }, 1000);
};

window.addEventListener('message', (event) => {
  const data = event.data;

  if (data.action === 'start') {
    app.classList.remove('hidden');
    startGame(data.payload, data.maxDuration);
  }

  if (data.action === 'hide') {
    app.classList.add('hidden');
    clearInterval(timerTick);
    game = null;
  }
});

replayBtn.addEventListener('click', () => {
  if (!game) return;
  if (!validateSourceSelection()) return;
  replaySequence();
});

guessBtn.addEventListener('click', submitGuess);

codeInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') submitGuess();
});

cardSelect.addEventListener('change', () => {
  if (!game) return;
  game.selectedCardId = cardSelect.value;

  const selected = getSelectedCard();
  if (selected) {
    sourceDescription.textContent = `Stolen Card: ${selected.holder} (${selected.masked}) from ${selected.bankName}.`;
  }
});

tierPicker.querySelectorAll('.tier').forEach(node => {
  node.addEventListener('click', () => {
    if (!game) return;
    if (!validateSourceSelection()) return;

    const tier = Number(node.dataset.tier);
    setTier(tier);
    regenerateByTier(tier);

    buildSequence();
    buildWires();
    buildCode();
    feedback.textContent = `Risk profile set: ${tierDescriptions[tier]}`;
  });
});

sourcePicker.querySelectorAll('.tier').forEach(node => {
  node.addEventListener('click', () => {
    if (!game) return;

    const sourceMode = node.dataset.source;

    if (sourceMode === 'card' && !game.cards.length) {
      feedback.textContent = 'No stolen cards available. Use /stealcard before selecting card mode.';
      return;
    }

    setSourceMode(sourceMode);

    const selected = getSelectedCard();
    if (sourceMode === 'card' && selected) {
      sourceDescription.textContent = `Card selected: ${selected.holder} ${selected.masked} (${selected.bankName}).`;
    }

    feedback.textContent = `Exploit source switched to ${sourceMode === 'card' ? 'stolen card' : 'ATM bus'} mode.`;
  });
});

document.getElementById('abortBtn').addEventListener('click', () => {
  if (game) {
    post('closeHack');
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && game) {
    post('closeHack');
  }
});
