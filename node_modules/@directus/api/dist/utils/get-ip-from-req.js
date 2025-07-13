import { useEnv } from '@directus/env';
import { isIP } from 'net';
import proxyAddr from 'proxy-addr';
import { useLogger } from '../logger/index.js';
/**
 * Generate the trusted ip list
 *
 * Adapted to have feature parity with the express equivalent https://github.com/expressjs/express/blob/9f4dbe3a1332cd883069ba9b73a9eed99234cfc7/lib/utils.js#L192
 */
function getTrustValue(trust) {
    if (typeof trust === 'boolean') {
        // Support plain true/false
        return (_addr, _i) => trust;
    }
    else if (typeof trust === 'number') {
        // Support trusting hop count
        return (_addr, i) => i < trust;
    }
    else if (typeof trust === 'string') {
        // Support comma-separated values
        trust = trust.split(',').map((v) => v.trim());
    }
    return proxyAddr.compile(trust || []);
}
export function getIPFromReq(req) {
    const env = useEnv();
    const logger = useLogger();
    let ip = 'ip' in req ? req.ip : proxyAddr(req, getTrustValue(env['IP_TRUST_PROXY']));
    if (env['IP_CUSTOM_HEADER']) {
        const customIPHeaderName = env['IP_CUSTOM_HEADER'].toLowerCase();
        // All req.headers are auto lower-cased
        let customIPHeaderValue = req.headers[customIPHeaderName];
        // // Done to have feature parity with https://github.com/expressjs/express/blob/9f4dbe3a1332cd883069ba9b73a9eed99234cfc7/lib/request.js#L63
        if (customIPHeaderName === 'referer' || customIPHeaderName === 'referrer') {
            customIPHeaderValue = req.headers['referrer'] || req.headers['referer'];
        }
        if (typeof customIPHeaderValue === 'string' && isIP(customIPHeaderValue) !== 0) {
            ip = customIPHeaderValue;
        }
        else {
            logger.warn(`Custom IP header didn't return valid IP address: ${JSON.stringify(customIPHeaderValue)}`);
        }
    }
    // IP addresses starting with ::ffff: are IPv4 addresses in IPv6 format. We can strip the prefix to get back to IPv4
    return ip?.startsWith('::ffff:') ? ip.substring(7) : ip ?? null;
}
