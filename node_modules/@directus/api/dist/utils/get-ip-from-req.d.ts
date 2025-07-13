import type { Request } from 'express';
import type { IncomingMessage } from 'http';
export declare function getIPFromReq(req: IncomingMessage | Request): string | null;
