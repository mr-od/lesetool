import { MaybeRef } from 'vue';
import { DeepPartial, Theme } from '@directus/types';
export declare const useFonts: (theme: MaybeRef<Theme | DeepPartial<Theme>>) => {
    googleFonts: import('vue').ComputedRef<string[]>;
};
