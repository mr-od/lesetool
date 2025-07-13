import { Router } from 'express';
import type { Client } from 'openid-client';
import { UsersService } from '../../services/users.js';
import type { AuthDriverOptions, User } from '../../types/index.js';
import type { RoleMap } from '../../types/rolemap.js';
import { LocalAuthDriver } from './local.js';
export declare class OAuth2AuthDriver extends LocalAuthDriver {
    client: Client;
    redirectUrl: string;
    usersService: UsersService;
    config: Record<string, any>;
    roleMap: RoleMap;
    constructor(options: AuthDriverOptions, config: Record<string, any>);
    generateCodeVerifier(): string;
    generateAuthUrl(codeVerifier: string, prompt?: boolean): string;
    private fetchUserId;
    getUserID(payload: Record<string, any>): Promise<string>;
    login(user: User): Promise<void>;
    refresh(user: User): Promise<void>;
}
export declare function createOAuth2AuthRouter(providerName: string): Router;
