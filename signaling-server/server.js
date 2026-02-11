const express = require('express');
const cors = require('cors');
require('dotenv').config();

const app = express();

// Enable CORS for all origins
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

// Parse JSON bodies
app.use(express.json());

// Log all requests with body
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
  if (req.body && Object.keys(req.body).length > 0) {
    console.log('  Body:', JSON.stringify(req.body));
  }
  next();
});

// In-memory storage for signals and rooms
const pendingSignals = new Map(); // peerId -> array of signals
const rooms = new Map(); // roomCode -> { peers: [], createdAt }
const activePeers = new Map(); // peerId -> { connectedAt, lastActivity, roomCode }

// Health check endpoint
app.get('/', (req, res) => {
  res.json({
    status: 'running',
    service: 'P2P Chat Signaling Server',
    timestamp: new Date().toISOString(),
    peers: activePeers.size,
    rooms: rooms.size
  });
});

// Server status endpoint
app.get('/status', (req, res) => {
  res.json({
    status: 'online',
    peers: activePeers.size,
    rooms: rooms.size,
    uptime: process.uptime()
  });
});

// Register peer and create/join room
app.post('/register', (req, res) => {
  let { peerId, roomCode, isInitiator } = req.body;
  
  console.log(`\n=== REGISTER REQUEST ===`);
  console.log(`Received: peerId=${peerId}, roomCode=${roomCode}, isInitiator=${isInitiator}`);
  
  // Generate peerId if not provided (for joiners)
  if (!peerId) {
    peerId = Math.floor(100000 + Math.random() * 900000).toString();
    console.log(`Generated peerId for joiner: ${peerId}`);
  }
  
  console.log(`Processing: peerId=${peerId}, roomCode=${roomCode}, isInitiator=${isInitiator}`);
  
  // Store peer
  activePeers.set(peerId, {
    connectedAt: new Date(),
    lastActivity: new Date(),
    roomCode: roomCode || peerId
  });
  
  let room = null;
  let finalRoomCode = roomCode || peerId;
  
  // If room code provided, join room
  if (roomCode) {
    console.log(`Looking for room: ${roomCode}`);
    room = rooms.get(roomCode);
    
    if (!room) {
      // ИСПРАВЛЕНИЕ: Если комнаты нет, мы создаем её и становимся Initiator.
      // Игнорируем то, что прислал клиент в isInitiator, так как сервер - источник истины.
      console.log(`Room ${roomCode} NOT FOUND. Creating room and setting peer as Initiator.`);
      room = { peers: [peerId], createdAt: new Date() };
      rooms.set(roomCode, room);
      isInitiator = true; // Принудительно устанавливаем true
      console.log(`Room ${roomCode} created by ${peerId} (initiator)`);
    } else {
      // Комната существует -> мы подключаемся как Joiner
      console.log(`Room ${roomCode} FOUND with peers: ${room.peers.join(', ')}`);
      isInitiator = false; // Принудительно устанавливаем false
      
      if (!room.peers.includes(peerId)) {
        room.peers.push(peerId);
        console.log(`Peer ${peerId} joined room ${roomCode} as joiner`);
        console.log(`Room now has peers: ${room.peers.join(', ')}`);
        
        // Notify other peers about new peer
        console.log(`Notifying existing peers about new peer ${peerId}...`);
        room.peers.forEach(otherPeerId => {
          if (otherPeerId !== peerId) {
            const signal = {
              type: 'peer-connected',
              from: peerId,
              to: otherPeerId,
              timestamp: new Date().toISOString()
            };
            console.log(`  -> Notifying peer ${otherPeerId} about ${peerId}`);
            addSignal(otherPeerId, signal);
          }
        });
        
        // Notify joiner about existing peers
        console.log(`Notifying joiner ${peerId} about existing peers...`);
        room.peers.forEach(otherPeerId => {
          if (otherPeerId !== peerId) {
            const signal = {
              type: 'peer-connected',
              from: otherPeerId,
              to: peerId,
              timestamp: new Date().toISOString()
            };
            console.log(`  -> Notifying ${peerId} about peer ${otherPeerId}`);
            addSignal(peerId, signal);
          }
        });
      } else {
        console.log(`Peer ${peerId} already in room ${roomCode}`);
      }
    }
    
    // Update peer's room
    activePeers.get(peerId).roomCode = roomCode;
  } else {
    // No room code provided, create personal room
    console.log(`No room code, creating personal room for ${peerId}`);
    room = { peers: [peerId], createdAt: new Date() };
    rooms.set(peerId, room);
    isInitiator = true;
    console.log(`Personal room ${peerId} created`);
  }
  
  console.log(`=== REGISTER SUCCESS ===`);
  console.log(`Returning: peerId=${peerId}, roomCode=${finalRoomCode}, isInitiator=${isInitiator}, peersInRoom=${room ? room.peers.length : 1}`);
  console.log(`Active rooms: ${rooms.size}, Active peers: ${activePeers.size}`);
  console.log('');
  
  // ИСПРАВЛЕНИЕ: Добавляем isInitiator в ответ клиенту!
  res.json({ 
    success: true, 
    peerId,
    roomCode: finalRoomCode,
    isInitiator: isInitiator, // <--- ВАЖНО: Отправляем роль клиенту
    peersInRoom: room ? room.peers : [peerId]
  });
});

// Send signal to another peer
app.post('/signal', (req, res) => {
  const { from, to, type, sdp, candidate } = req.body;
  
  if (!from || !to || !type) {
    return res.status(400).json({ error: 'from, to, and type are required' });
  }
  
  console.log(`Signal ${type} from ${from} to ${to}`);
  
  const signal = {
    type,
    from,
    to,
    sdp,
    candidate,
    timestamp: new Date().toISOString()
  };
  
  // Add to recipient's pending signals
  addSignal(to, signal);
  
  // Update sender activity
  if (activePeers.has(from)) {
    activePeers.get(from).lastActivity = new Date();
  }
  
  res.json({ success: true });
});

// Poll for incoming signals
app.get('/poll', (req, res) => {
  const { peerId } = req.query;
  
  if (!peerId) {
    console.log('Poll request: MISSING peerId!');
    return res.status(400).json({ error: 'peerId is required' });
  }
  
  // Update activity
  if (activePeers.has(peerId)) {
    activePeers.get(peerId).lastActivity = new Date();
  }
  
  // Get and clear pending signals for this peer
  const signals = pendingSignals.get(peerId) || [];
  const signalCount = signals.length;
  pendingSignals.set(peerId, []);
  
  if (signalCount > 0) {
    console.log(`Poll: Returning ${signalCount} signals to peer ${peerId}`);
    signals.forEach((s, i) => {
      console.log(`  [${i}] type=${s.type} from=${s.from}`);
    });
  }
  
  res.json({ signals });
});

// Join room endpoint (legacy)
app.post('/join', (req, res) => {
  const { peerId, roomCode } = req.body;
  
  if (!peerId || !roomCode) {
    return res.status(400).json({ error: 'peerId and roomCode are required' });
  }
  
  let room = rooms.get(roomCode);
  
  if (!room) {
    return res.status(404).json({ error: 'Room not found' });
  }
  
  if (!room.peers.includes(peerId)) {
    room.peers.push(peerId);
    
    // Notify other peers
    room.peers.forEach(otherPeerId => {
      if (otherPeerId !== peerId) {
        addSignal(otherPeerId, {
          type: 'peer-connected',
          from: peerId,
          to: otherPeerId,
          timestamp: new Date().toISOString()
        });
      }
    });
  }
  
  res.json({ 
    success: true, 
    roomCode,
    peers: room.peers 
  });
});

// Disconnect peer
app.post('/disconnect', (req, res) => {
  const { peerId } = req.body;
  
  if (peerId && activePeers.has(peerId)) {
    const peer = activePeers.get(peerId);
    
    // Remove from room
    if (peer.roomCode && rooms.has(peer.roomCode)) {
      const room = rooms.get(peer.roomCode);
      room.peers = room.peers.filter(id => id !== peerId);
      
      // Notify other peers
      room.peers.forEach(otherPeerId => {
        addSignal(otherPeerId, {
          type: 'peer-disconnected',
          from: peerId,
          timestamp: new Date().toISOString()
        });
      });
      
      // Clean up empty room
      if (room.peers.length === 0) {
        rooms.delete(peer.roomCode);
        console.log(`Room ${peer.roomCode} deleted (empty)`);
      }
    }
    
    activePeers.delete(peerId);
    pendingSignals.delete(peerId);
    console.log(`Peer ${peerId} disconnected`);
  }
  
  res.json({ success: true });
});

// Helper function to add signal to peer's queue
function addSignal(peerId, signal) {
  console.log(`  Adding signal type=${signal.type} to peer ${peerId}'s queue`);
  if (!pendingSignals.has(peerId)) {
    pendingSignals.set(peerId, []);
    console.log(`  Created new signal queue for peer ${peerId}`);
  }
  pendingSignals.get(peerId).push(signal);
  console.log(`  Signal added. Queue size for ${peerId}: ${pendingSignals.get(peerId).length}`);
}

// Cleanup inactive peers every 5 minutes
setInterval(() => {
  const now = new Date();
  const timeout = 5 * 60 * 1000; // 5 minutes
  
  for (const [peerId, peer] of activePeers.entries()) {
    if (now - peer.lastActivity > timeout) {
      console.log(`Removing inactive peer: ${peerId}`);
      
      // Remove from room
      if (peer.roomCode && rooms.has(peer.roomCode)) {
        const room = rooms.get(peer.roomCode);
        room.peers = room.peers.filter(id => id !== peerId);
        
        if (room.peers.length === 0) {
          rooms.delete(peer.roomCode);
        }
      }
      
      activePeers.delete(peerId);
      pendingSignals.delete(peerId);
    }
  }
}, 60 * 1000); // Check every minute

// Express server
const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';

app.listen(PORT, HOST, () => {
  console.log(`\n========================================`);
  console.log(`P2P Chat Signaling Server`);
  console.log(`========================================`);
  console.log(`HTTP server: http://${HOST}:${PORT}`);
  console.log(`\nEndpoints:`);
  console.log(`  POST /register - Register peer and create/join room`);
  console.log(`  POST /signal   - Send WebRTC signal (offer/answer/ice)`);
  console.log(`  GET  /poll     - Poll for incoming signals`);
  console.log(`  POST /join     - Join existing room`);
  console.log(`  POST /disconnect - Disconnect peer`);
  console.log(`\nTo connect from Android:`);
  console.log(`  1. Use http://YOUR_PC_IP:${PORT}`);
  console.log(`  2. Both devices must be on same WiFi`);
  console.log(`========================================\n`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down gracefully');
  process.exit(0);
});
