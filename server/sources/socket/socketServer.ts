import { Server as HttpServer } from 'http';
import { Server } from 'socket.io';
import { verifyToken } from '@/auth/crypto';
import { config } from '@/config';
import { EventRouter, type ClientConnection } from './eventRouter';
import { registerSessionHandler } from './sessionHandler';
import { registerRpcHandler } from './rpcHandler';

export const eventRouter = new EventRouter();

export function startSocket(server: HttpServer) {
    const io = new Server(server, {
        cors: { origin: '*', methods: ['GET', 'POST', 'OPTIONS'] },
        transports: ['websocket', 'polling'],
        pingTimeout: 45000,
        pingInterval: 15000,
        path: '/v1/updates',
        connectTimeout: 20000,
    });

    io.on('connection', (socket) => {
        const token = socket.handshake.auth.token as string | undefined;
        const clientType = (socket.handshake.auth.clientType as string) || 'user-scoped';
        const sessionId = socket.handshake.auth.sessionId as string | undefined;

        if (!token) {
            socket.disconnect();
            return;
        }

        const payload = verifyToken(token, config.masterSecret);
        if (!payload) {
            socket.disconnect();
            return;
        }

        const connection: ClientConnection = {
            connectionType: clientType === 'session-scoped' ? 'session-scoped' : 'user-scoped',
            socket,
            deviceId: payload.deviceId,
            sessionId,
        };

        eventRouter.addConnection(payload.deviceId, connection);

        registerSessionHandler(socket, payload.deviceId, eventRouter);
        registerRpcHandler(socket, payload.deviceId);

        socket.on('disconnect', () => {
            eventRouter.removeConnection(payload.deviceId, connection);
        });
    });

    return io;
}
