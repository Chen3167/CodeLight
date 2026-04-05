import type { Socket } from 'socket.io';

const rpcHandlers = new Map<string, Socket>();

export function registerRpcHandler(socket: Socket, deviceId: string) {

    socket.on('rpc-register', (data: { method: string }) => {
        rpcHandlers.set(data.method, socket);
    });

    socket.on('rpc-unregister', (data: { method: string }) => {
        if (rpcHandlers.get(data.method) === socket) {
            rpcHandlers.delete(data.method);
        }
    });

    socket.on('rpc-call', async (data: {
        method: string;
        params: string;
    }, callback?: (result: any) => void) => {
        const handler = rpcHandlers.get(data.method);
        if (!handler || !handler.connected) {
            callback?.({ ok: false, error: 'No handler registered' });
            return;
        }

        try {
            const result = await handler.timeout(300_000).emitWithAck('rpc-call', {
                method: data.method,
                params: data.params,
            });
            callback?.(result);
        } catch {
            callback?.({ ok: false, error: 'RPC timeout' });
        }
    });

    socket.on('disconnect', () => {
        for (const [method, s] of rpcHandlers.entries()) {
            if (s === socket) rpcHandlers.delete(method);
        }
    });
}
