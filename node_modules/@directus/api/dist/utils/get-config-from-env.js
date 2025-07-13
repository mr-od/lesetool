import { useEnv } from '@directus/env';
import { toArray } from '@directus/utils';
import camelcase from 'camelcase';
import { set } from 'lodash-es';
export function getConfigFromEnv(prefix, options) {
    const env = useEnv();
    const type = options?.type ?? 'camelcase';
    const config = {};
    const lowerCasePrefix = prefix.toLowerCase();
    const omitKeys = toArray(options?.omitKey ?? []).map((key) => key.toLowerCase());
    const omitPrefixes = toArray(options?.omitPrefix ?? []).map((prefix) => prefix.toLowerCase());
    for (const [key, value] of Object.entries(env)) {
        const lowerCaseKey = key.toLowerCase();
        if (lowerCaseKey.startsWith(lowerCasePrefix) === false)
            continue;
        if (omitKeys.length > 0) {
            const isKeyInOmitKeys = omitKeys.some((keyToOmit) => lowerCaseKey === keyToOmit);
            if (isKeyInOmitKeys)
                continue;
        }
        if (omitPrefixes.length > 0) {
            const keyStartsWithAnyPrefix = omitPrefixes.some((prefix) => lowerCaseKey.startsWith(prefix));
            if (keyStartsWithAnyPrefix)
                continue;
        }
        if (key.includes('__')) {
            const path = key
                .split('__')
                .map((key, index) => (index === 0 ? transform(transform(key.slice(prefix.length))) : transform(key)));
            set(config, path.join('.'), value);
        }
        else {
            config[transform(key.slice(prefix.length))] = value;
        }
    }
    return config;
    function transform(key) {
        if (type === 'camelcase') {
            return camelcase(key, { locale: false });
        }
        else if (type === 'underscore') {
            return key.toLowerCase();
        }
        return key;
    }
}
