const express = require('express');
const http = require('http');
const socketIo = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = socketIo(server);

let chatRooms = {};

io.on('connection', (socket) => {
    socket.on('join room', (data) => {
        const { roomCode, username } = data;

        socket.join(roomCode);
        socket.username = username;
        socket.roomCode = roomCode;

        if (!chatRooms[roomCode]) chatRooms[roomCode] = [];
        io.to(roomCode).emit('system message', `${username} joined the room`);
    });

    socket.on('chat message', (msg) => {
        const { roomCode } = socket;
        if (chatRooms[roomCode]) {
            io.to(roomCode).emit('chat message', msg);
        }
    });

    socket.on('send media', (media) => {
        const { roomCode } = socket;
        if (chatRooms[roomCode]) {
            io.to(roomCode).emit('media message', media);
        }
    });
});

server.listen(3000, () => console.log('Server running on port 3000'));
