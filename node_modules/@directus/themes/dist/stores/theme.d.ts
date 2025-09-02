import { Theme } from '@directus/types';
export declare const useThemeStore: import('pinia').StoreDefinition<"🎨 Themes", Pick<{
    themes: {
        light: {
            id: string;
            name: string;
            appearance: "light" | "dark";
            rules: {
                borderRadius?: string;
                borderWidth?: string;
                foreground?: string;
                foregroundSubdued?: string;
                foregroundAccent?: string;
                background?: string;
                backgroundNormal?: string;
                backgroundAccent?: string;
                backgroundSubdued?: string;
                borderColor?: string;
                borderColorAccent?: string;
                borderColorSubdued?: string;
                primary?: string;
                primaryBackground?: string;
                primarySubdued?: string;
                primaryAccent?: string;
                secondary?: string;
                secondaryBackground?: string;
                secondarySubdued?: string;
                secondaryAccent?: string;
                success?: string;
                successBackground?: string;
                successSubdued?: string;
                successAccent?: string;
                warning?: string;
                warningBackground?: string;
                warningSubdued?: string;
                warningAccent?: string;
                danger?: string;
                dangerBackground?: string;
                dangerSubdued?: string;
                dangerAccent?: string;
                fonts?: {
                    display?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    sans?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    serif?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    monospace?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
                navigation?: {
                    borderWidth?: string;
                    background?: string;
                    backgroundAccent?: string;
                    borderColor?: string;
                    project?: {
                        borderWidth?: string;
                        foreground?: string;
                        background?: string;
                        borderColor?: string;
                        fontFamily?: string;
                    };
                    modules?: {
                        borderWidth?: string;
                        background?: string;
                        borderColor?: string;
                        button?: {
                            foreground?: string;
                            background?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                            backgroundHover?: string;
                            backgroundActive?: string;
                        };
                    };
                    list?: {
                        foreground?: string;
                        background?: string;
                        fontFamily?: string;
                        foregroundHover?: string;
                        foregroundActive?: string;
                        backgroundHover?: string;
                        backgroundActive?: string;
                        icon?: {
                            foreground?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                        };
                        divider: {
                            borderWidth?: string;
                            borderColor?: string;
                        };
                    };
                };
                header?: {
                    borderWidth?: string;
                    background?: string;
                    borderColor?: string;
                    boxShadow?: string;
                    headline?: {
                        foreground?: string;
                        fontFamily?: string;
                    };
                    title?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
                form?: {
                    columnGap?: string;
                    rowGap?: string;
                    field?: {
                        label?: {
                            foreground?: string;
                            fontFamily?: string;
                            fontWeight?: string;
                        };
                        input?: {
                            foreground?: string;
                            foregroundSubdued?: string;
                            background?: string;
                            backgroundSubdued?: string;
                            borderColor?: string;
                            boxShadow?: string;
                            borderColorHover?: string;
                            borderColorFocus?: string;
                            boxShadowHover?: string;
                            boxShadowFocus?: string;
                            height?: string;
                            padding?: string;
                        };
                    };
                };
                sidebar?: {
                    borderWidth?: string;
                    foreground?: string;
                    background?: string;
                    borderColor?: string;
                    fontFamily?: string;
                    section?: {
                        form?: {
                            columnGap?: string;
                            rowGap?: string;
                            field?: {
                                label?: {
                                    foreground?: string;
                                    fontFamily?: string;
                                    fontWeight?: string;
                                };
                                input?: {
                                    foreground?: string;
                                    foregroundSubdued?: string;
                                    background?: string;
                                    backgroundSubdued?: string;
                                    borderColor?: string;
                                    boxShadow?: string;
                                    borderColorHover?: string;
                                    borderColorFocus?: string;
                                    boxShadowHover?: string;
                                    boxShadowFocus?: string;
                                    height?: string;
                                    padding?: string;
                                };
                            };
                        };
                        toggle?: {
                            borderWidth?: string;
                            foreground?: string;
                            background?: string;
                            borderColor?: string;
                            fontFamily?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                            backgroundHover?: string;
                            backgroundActive?: string;
                            icon?: {
                                foreground?: string;
                                foregroundHover?: string;
                                foregroundActive?: string;
                            };
                        };
                    };
                };
                public?: {
                    foreground?: string;
                    foregroundAccent?: string;
                    background?: string;
                    form?: {
                        columnGap?: string;
                        rowGap?: string;
                        field?: {
                            label?: {
                                foreground?: string;
                                fontFamily?: string;
                                fontWeight?: string;
                            };
                            input?: {
                                foreground?: string;
                                foregroundSubdued?: string;
                                background?: string;
                                backgroundSubdued?: string;
                                borderColor?: string;
                                boxShadow?: string;
                                borderColorHover?: string;
                                borderColorFocus?: string;
                                boxShadowHover?: string;
                                boxShadowFocus?: string;
                                height?: string;
                                padding?: string;
                            };
                        };
                    };
                    art?: {
                        background?: string;
                        primary?: string;
                        secondary?: string;
                        speed?: string;
                    };
                };
                popover?: {
                    menu?: {
                        borderRadius?: string;
                        background?: string;
                        boxShadow?: string;
                    };
                };
                banner?: {
                    borderRadius?: string;
                    background?: string;
                    headline?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    title?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    padding?: string;
                    art?: {
                        foreground?: string;
                    };
                    avatar?: {
                        borderRadius?: string;
                        foreground?: string;
                        background?: string;
                    };
                    subtitle?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
            };
        }[];
        dark: {
            id: string;
            name: string;
            appearance: "light" | "dark";
            rules: {
                borderRadius?: string;
                borderWidth?: string;
                foreground?: string;
                foregroundSubdued?: string;
                foregroundAccent?: string;
                background?: string;
                backgroundNormal?: string;
                backgroundAccent?: string;
                backgroundSubdued?: string;
                borderColor?: string;
                borderColorAccent?: string;
                borderColorSubdued?: string;
                primary?: string;
                primaryBackground?: string;
                primarySubdued?: string;
                primaryAccent?: string;
                secondary?: string;
                secondaryBackground?: string;
                secondarySubdued?: string;
                secondaryAccent?: string;
                success?: string;
                successBackground?: string;
                successSubdued?: string;
                successAccent?: string;
                warning?: string;
                warningBackground?: string;
                warningSubdued?: string;
                warningAccent?: string;
                danger?: string;
                dangerBackground?: string;
                dangerSubdued?: string;
                dangerAccent?: string;
                fonts?: {
                    display?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    sans?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    serif?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    monospace?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
                navigation?: {
                    borderWidth?: string;
                    background?: string;
                    backgroundAccent?: string;
                    borderColor?: string;
                    project?: {
                        borderWidth?: string;
                        foreground?: string;
                        background?: string;
                        borderColor?: string;
                        fontFamily?: string;
                    };
                    modules?: {
                        borderWidth?: string;
                        background?: string;
                        borderColor?: string;
                        button?: {
                            foreground?: string;
                            background?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                            backgroundHover?: string;
                            backgroundActive?: string;
                        };
                    };
                    list?: {
                        foreground?: string;
                        background?: string;
                        fontFamily?: string;
                        foregroundHover?: string;
                        foregroundActive?: string;
                        backgroundHover?: string;
                        backgroundActive?: string;
                        icon?: {
                            foreground?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                        };
                        divider: {
                            borderWidth?: string;
                            borderColor?: string;
                        };
                    };
                };
                header?: {
                    borderWidth?: string;
                    background?: string;
                    borderColor?: string;
                    boxShadow?: string;
                    headline?: {
                        foreground?: string;
                        fontFamily?: string;
                    };
                    title?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
                form?: {
                    columnGap?: string;
                    rowGap?: string;
                    field?: {
                        label?: {
                            foreground?: string;
                            fontFamily?: string;
                            fontWeight?: string;
                        };
                        input?: {
                            foreground?: string;
                            foregroundSubdued?: string;
                            background?: string;
                            backgroundSubdued?: string;
                            borderColor?: string;
                            boxShadow?: string;
                            borderColorHover?: string;
                            borderColorFocus?: string;
                            boxShadowHover?: string;
                            boxShadowFocus?: string;
                            height?: string;
                            padding?: string;
                        };
                    };
                };
                sidebar?: {
                    borderWidth?: string;
                    foreground?: string;
                    background?: string;
                    borderColor?: string;
                    fontFamily?: string;
                    section?: {
                        form?: {
                            columnGap?: string;
                            rowGap?: string;
                            field?: {
                                label?: {
                                    foreground?: string;
                                    fontFamily?: string;
                                    fontWeight?: string;
                                };
                                input?: {
                                    foreground?: string;
                                    foregroundSubdued?: string;
                                    background?: string;
                                    backgroundSubdued?: string;
                                    borderColor?: string;
                                    boxShadow?: string;
                                    borderColorHover?: string;
                                    borderColorFocus?: string;
                                    boxShadowHover?: string;
                                    boxShadowFocus?: string;
                                    height?: string;
                                    padding?: string;
                                };
                            };
                        };
                        toggle?: {
                            borderWidth?: string;
                            foreground?: string;
                            background?: string;
                            borderColor?: string;
                            fontFamily?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                            backgroundHover?: string;
                            backgroundActive?: string;
                            icon?: {
                                foreground?: string;
                                foregroundHover?: string;
                                foregroundActive?: string;
                            };
                        };
                    };
                };
                public?: {
                    foreground?: string;
                    foregroundAccent?: string;
                    background?: string;
                    form?: {
                        columnGap?: string;
                        rowGap?: string;
                        field?: {
                            label?: {
                                foreground?: string;
                                fontFamily?: string;
                                fontWeight?: string;
                            };
                            input?: {
                                foreground?: string;
                                foregroundSubdued?: string;
                                background?: string;
                                backgroundSubdued?: string;
                                borderColor?: string;
                                boxShadow?: string;
                                borderColorHover?: string;
                                borderColorFocus?: string;
                                boxShadowHover?: string;
                                boxShadowFocus?: string;
                                height?: string;
                                padding?: string;
                            };
                        };
                    };
                    art?: {
                        background?: string;
                        primary?: string;
                        secondary?: string;
                        speed?: string;
                    };
                };
                popover?: {
                    menu?: {
                        borderRadius?: string;
                        background?: string;
                        boxShadow?: string;
                    };
                };
                banner?: {
                    borderRadius?: string;
                    background?: string;
                    headline?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    title?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    padding?: string;
                    art?: {
                        foreground?: string;
                    };
                    avatar?: {
                        borderRadius?: string;
                        foreground?: string;
                        background?: string;
                    };
                    subtitle?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
            };
        }[];
    };
    registerTheme: (theme: Theme) => void;
}, "themes">, Pick<{
    themes: {
        light: {
            id: string;
            name: string;
            appearance: "light" | "dark";
            rules: {
                borderRadius?: string;
                borderWidth?: string;
                foreground?: string;
                foregroundSubdued?: string;
                foregroundAccent?: string;
                background?: string;
                backgroundNormal?: string;
                backgroundAccent?: string;
                backgroundSubdued?: string;
                borderColor?: string;
                borderColorAccent?: string;
                borderColorSubdued?: string;
                primary?: string;
                primaryBackground?: string;
                primarySubdued?: string;
                primaryAccent?: string;
                secondary?: string;
                secondaryBackground?: string;
                secondarySubdued?: string;
                secondaryAccent?: string;
                success?: string;
                successBackground?: string;
                successSubdued?: string;
                successAccent?: string;
                warning?: string;
                warningBackground?: string;
                warningSubdued?: string;
                warningAccent?: string;
                danger?: string;
                dangerBackground?: string;
                dangerSubdued?: string;
                dangerAccent?: string;
                fonts?: {
                    display?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    sans?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    serif?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    monospace?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
                navigation?: {
                    borderWidth?: string;
                    background?: string;
                    backgroundAccent?: string;
                    borderColor?: string;
                    project?: {
                        borderWidth?: string;
                        foreground?: string;
                        background?: string;
                        borderColor?: string;
                        fontFamily?: string;
                    };
                    modules?: {
                        borderWidth?: string;
                        background?: string;
                        borderColor?: string;
                        button?: {
                            foreground?: string;
                            background?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                            backgroundHover?: string;
                            backgroundActive?: string;
                        };
                    };
                    list?: {
                        foreground?: string;
                        background?: string;
                        fontFamily?: string;
                        foregroundHover?: string;
                        foregroundActive?: string;
                        backgroundHover?: string;
                        backgroundActive?: string;
                        icon?: {
                            foreground?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                        };
                        divider: {
                            borderWidth?: string;
                            borderColor?: string;
                        };
                    };
                };
                header?: {
                    borderWidth?: string;
                    background?: string;
                    borderColor?: string;
                    boxShadow?: string;
                    headline?: {
                        foreground?: string;
                        fontFamily?: string;
                    };
                    title?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
                form?: {
                    columnGap?: string;
                    rowGap?: string;
                    field?: {
                        label?: {
                            foreground?: string;
                            fontFamily?: string;
                            fontWeight?: string;
                        };
                        input?: {
                            foreground?: string;
                            foregroundSubdued?: string;
                            background?: string;
                            backgroundSubdued?: string;
                            borderColor?: string;
                            boxShadow?: string;
                            borderColorHover?: string;
                            borderColorFocus?: string;
                            boxShadowHover?: string;
                            boxShadowFocus?: string;
                            height?: string;
                            padding?: string;
                        };
                    };
                };
                sidebar?: {
                    borderWidth?: string;
                    foreground?: string;
                    background?: string;
                    borderColor?: string;
                    fontFamily?: string;
                    section?: {
                        form?: {
                            columnGap?: string;
                            rowGap?: string;
                            field?: {
                                label?: {
                                    foreground?: string;
                                    fontFamily?: string;
                                    fontWeight?: string;
                                };
                                input?: {
                                    foreground?: string;
                                    foregroundSubdued?: string;
                                    background?: string;
                                    backgroundSubdued?: string;
                                    borderColor?: string;
                                    boxShadow?: string;
                                    borderColorHover?: string;
                                    borderColorFocus?: string;
                                    boxShadowHover?: string;
                                    boxShadowFocus?: string;
                                    height?: string;
                                    padding?: string;
                                };
                            };
                        };
                        toggle?: {
                            borderWidth?: string;
                            foreground?: string;
                            background?: string;
                            borderColor?: string;
                            fontFamily?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                            backgroundHover?: string;
                            backgroundActive?: string;
                            icon?: {
                                foreground?: string;
                                foregroundHover?: string;
                                foregroundActive?: string;
                            };
                        };
                    };
                };
                public?: {
                    foreground?: string;
                    foregroundAccent?: string;
                    background?: string;
                    form?: {
                        columnGap?: string;
                        rowGap?: string;
                        field?: {
                            label?: {
                                foreground?: string;
                                fontFamily?: string;
                                fontWeight?: string;
                            };
                            input?: {
                                foreground?: string;
                                foregroundSubdued?: string;
                                background?: string;
                                backgroundSubdued?: string;
                                borderColor?: string;
                                boxShadow?: string;
                                borderColorHover?: string;
                                borderColorFocus?: string;
                                boxShadowHover?: string;
                                boxShadowFocus?: string;
                                height?: string;
                                padding?: string;
                            };
                        };
                    };
                    art?: {
                        background?: string;
                        primary?: string;
                        secondary?: string;
                        speed?: string;
                    };
                };
                popover?: {
                    menu?: {
                        borderRadius?: string;
                        background?: string;
                        boxShadow?: string;
                    };
                };
                banner?: {
                    borderRadius?: string;
                    background?: string;
                    headline?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    title?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    padding?: string;
                    art?: {
                        foreground?: string;
                    };
                    avatar?: {
                        borderRadius?: string;
                        foreground?: string;
                        background?: string;
                    };
                    subtitle?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
            };
        }[];
        dark: {
            id: string;
            name: string;
            appearance: "light" | "dark";
            rules: {
                borderRadius?: string;
                borderWidth?: string;
                foreground?: string;
                foregroundSubdued?: string;
                foregroundAccent?: string;
                background?: string;
                backgroundNormal?: string;
                backgroundAccent?: string;
                backgroundSubdued?: string;
                borderColor?: string;
                borderColorAccent?: string;
                borderColorSubdued?: string;
                primary?: string;
                primaryBackground?: string;
                primarySubdued?: string;
                primaryAccent?: string;
                secondary?: string;
                secondaryBackground?: string;
                secondarySubdued?: string;
                secondaryAccent?: string;
                success?: string;
                successBackground?: string;
                successSubdued?: string;
                successAccent?: string;
                warning?: string;
                warningBackground?: string;
                warningSubdued?: string;
                warningAccent?: string;
                danger?: string;
                dangerBackground?: string;
                dangerSubdued?: string;
                dangerAccent?: string;
                fonts?: {
                    display?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    sans?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    serif?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    monospace?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
                navigation?: {
                    borderWidth?: string;
                    background?: string;
                    backgroundAccent?: string;
                    borderColor?: string;
                    project?: {
                        borderWidth?: string;
                        foreground?: string;
                        background?: string;
                        borderColor?: string;
                        fontFamily?: string;
                    };
                    modules?: {
                        borderWidth?: string;
                        background?: string;
                        borderColor?: string;
                        button?: {
                            foreground?: string;
                            background?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                            backgroundHover?: string;
                            backgroundActive?: string;
                        };
                    };
                    list?: {
                        foreground?: string;
                        background?: string;
                        fontFamily?: string;
                        foregroundHover?: string;
                        foregroundActive?: string;
                        backgroundHover?: string;
                        backgroundActive?: string;
                        icon?: {
                            foreground?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                        };
                        divider: {
                            borderWidth?: string;
                            borderColor?: string;
                        };
                    };
                };
                header?: {
                    borderWidth?: string;
                    background?: string;
                    borderColor?: string;
                    boxShadow?: string;
                    headline?: {
                        foreground?: string;
                        fontFamily?: string;
                    };
                    title?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
                form?: {
                    columnGap?: string;
                    rowGap?: string;
                    field?: {
                        label?: {
                            foreground?: string;
                            fontFamily?: string;
                            fontWeight?: string;
                        };
                        input?: {
                            foreground?: string;
                            foregroundSubdued?: string;
                            background?: string;
                            backgroundSubdued?: string;
                            borderColor?: string;
                            boxShadow?: string;
                            borderColorHover?: string;
                            borderColorFocus?: string;
                            boxShadowHover?: string;
                            boxShadowFocus?: string;
                            height?: string;
                            padding?: string;
                        };
                    };
                };
                sidebar?: {
                    borderWidth?: string;
                    foreground?: string;
                    background?: string;
                    borderColor?: string;
                    fontFamily?: string;
                    section?: {
                        form?: {
                            columnGap?: string;
                            rowGap?: string;
                            field?: {
                                label?: {
                                    foreground?: string;
                                    fontFamily?: string;
                                    fontWeight?: string;
                                };
                                input?: {
                                    foreground?: string;
                                    foregroundSubdued?: string;
                                    background?: string;
                                    backgroundSubdued?: string;
                                    borderColor?: string;
                                    boxShadow?: string;
                                    borderColorHover?: string;
                                    borderColorFocus?: string;
                                    boxShadowHover?: string;
                                    boxShadowFocus?: string;
                                    height?: string;
                                    padding?: string;
                                };
                            };
                        };
                        toggle?: {
                            borderWidth?: string;
                            foreground?: string;
                            background?: string;
                            borderColor?: string;
                            fontFamily?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                            backgroundHover?: string;
                            backgroundActive?: string;
                            icon?: {
                                foreground?: string;
                                foregroundHover?: string;
                                foregroundActive?: string;
                            };
                        };
                    };
                };
                public?: {
                    foreground?: string;
                    foregroundAccent?: string;
                    background?: string;
                    form?: {
                        columnGap?: string;
                        rowGap?: string;
                        field?: {
                            label?: {
                                foreground?: string;
                                fontFamily?: string;
                                fontWeight?: string;
                            };
                            input?: {
                                foreground?: string;
                                foregroundSubdued?: string;
                                background?: string;
                                backgroundSubdued?: string;
                                borderColor?: string;
                                boxShadow?: string;
                                borderColorHover?: string;
                                borderColorFocus?: string;
                                boxShadowHover?: string;
                                boxShadowFocus?: string;
                                height?: string;
                                padding?: string;
                            };
                        };
                    };
                    art?: {
                        background?: string;
                        primary?: string;
                        secondary?: string;
                        speed?: string;
                    };
                };
                popover?: {
                    menu?: {
                        borderRadius?: string;
                        background?: string;
                        boxShadow?: string;
                    };
                };
                banner?: {
                    borderRadius?: string;
                    background?: string;
                    headline?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    title?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    padding?: string;
                    art?: {
                        foreground?: string;
                    };
                    avatar?: {
                        borderRadius?: string;
                        foreground?: string;
                        background?: string;
                    };
                    subtitle?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
            };
        }[];
    };
    registerTheme: (theme: Theme) => void;
}, never>, Pick<{
    themes: {
        light: {
            id: string;
            name: string;
            appearance: "light" | "dark";
            rules: {
                borderRadius?: string;
                borderWidth?: string;
                foreground?: string;
                foregroundSubdued?: string;
                foregroundAccent?: string;
                background?: string;
                backgroundNormal?: string;
                backgroundAccent?: string;
                backgroundSubdued?: string;
                borderColor?: string;
                borderColorAccent?: string;
                borderColorSubdued?: string;
                primary?: string;
                primaryBackground?: string;
                primarySubdued?: string;
                primaryAccent?: string;
                secondary?: string;
                secondaryBackground?: string;
                secondarySubdued?: string;
                secondaryAccent?: string;
                success?: string;
                successBackground?: string;
                successSubdued?: string;
                successAccent?: string;
                warning?: string;
                warningBackground?: string;
                warningSubdued?: string;
                warningAccent?: string;
                danger?: string;
                dangerBackground?: string;
                dangerSubdued?: string;
                dangerAccent?: string;
                fonts?: {
                    display?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    sans?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    serif?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    monospace?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
                navigation?: {
                    borderWidth?: string;
                    background?: string;
                    backgroundAccent?: string;
                    borderColor?: string;
                    project?: {
                        borderWidth?: string;
                        foreground?: string;
                        background?: string;
                        borderColor?: string;
                        fontFamily?: string;
                    };
                    modules?: {
                        borderWidth?: string;
                        background?: string;
                        borderColor?: string;
                        button?: {
                            foreground?: string;
                            background?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                            backgroundHover?: string;
                            backgroundActive?: string;
                        };
                    };
                    list?: {
                        foreground?: string;
                        background?: string;
                        fontFamily?: string;
                        foregroundHover?: string;
                        foregroundActive?: string;
                        backgroundHover?: string;
                        backgroundActive?: string;
                        icon?: {
                            foreground?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                        };
                        divider: {
                            borderWidth?: string;
                            borderColor?: string;
                        };
                    };
                };
                header?: {
                    borderWidth?: string;
                    background?: string;
                    borderColor?: string;
                    boxShadow?: string;
                    headline?: {
                        foreground?: string;
                        fontFamily?: string;
                    };
                    title?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
                form?: {
                    columnGap?: string;
                    rowGap?: string;
                    field?: {
                        label?: {
                            foreground?: string;
                            fontFamily?: string;
                            fontWeight?: string;
                        };
                        input?: {
                            foreground?: string;
                            foregroundSubdued?: string;
                            background?: string;
                            backgroundSubdued?: string;
                            borderColor?: string;
                            boxShadow?: string;
                            borderColorHover?: string;
                            borderColorFocus?: string;
                            boxShadowHover?: string;
                            boxShadowFocus?: string;
                            height?: string;
                            padding?: string;
                        };
                    };
                };
                sidebar?: {
                    borderWidth?: string;
                    foreground?: string;
                    background?: string;
                    borderColor?: string;
                    fontFamily?: string;
                    section?: {
                        form?: {
                            columnGap?: string;
                            rowGap?: string;
                            field?: {
                                label?: {
                                    foreground?: string;
                                    fontFamily?: string;
                                    fontWeight?: string;
                                };
                                input?: {
                                    foreground?: string;
                                    foregroundSubdued?: string;
                                    background?: string;
                                    backgroundSubdued?: string;
                                    borderColor?: string;
                                    boxShadow?: string;
                                    borderColorHover?: string;
                                    borderColorFocus?: string;
                                    boxShadowHover?: string;
                                    boxShadowFocus?: string;
                                    height?: string;
                                    padding?: string;
                                };
                            };
                        };
                        toggle?: {
                            borderWidth?: string;
                            foreground?: string;
                            background?: string;
                            borderColor?: string;
                            fontFamily?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                            backgroundHover?: string;
                            backgroundActive?: string;
                            icon?: {
                                foreground?: string;
                                foregroundHover?: string;
                                foregroundActive?: string;
                            };
                        };
                    };
                };
                public?: {
                    foreground?: string;
                    foregroundAccent?: string;
                    background?: string;
                    form?: {
                        columnGap?: string;
                        rowGap?: string;
                        field?: {
                            label?: {
                                foreground?: string;
                                fontFamily?: string;
                                fontWeight?: string;
                            };
                            input?: {
                                foreground?: string;
                                foregroundSubdued?: string;
                                background?: string;
                                backgroundSubdued?: string;
                                borderColor?: string;
                                boxShadow?: string;
                                borderColorHover?: string;
                                borderColorFocus?: string;
                                boxShadowHover?: string;
                                boxShadowFocus?: string;
                                height?: string;
                                padding?: string;
                            };
                        };
                    };
                    art?: {
                        background?: string;
                        primary?: string;
                        secondary?: string;
                        speed?: string;
                    };
                };
                popover?: {
                    menu?: {
                        borderRadius?: string;
                        background?: string;
                        boxShadow?: string;
                    };
                };
                banner?: {
                    borderRadius?: string;
                    background?: string;
                    headline?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    title?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    padding?: string;
                    art?: {
                        foreground?: string;
                    };
                    avatar?: {
                        borderRadius?: string;
                        foreground?: string;
                        background?: string;
                    };
                    subtitle?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
            };
        }[];
        dark: {
            id: string;
            name: string;
            appearance: "light" | "dark";
            rules: {
                borderRadius?: string;
                borderWidth?: string;
                foreground?: string;
                foregroundSubdued?: string;
                foregroundAccent?: string;
                background?: string;
                backgroundNormal?: string;
                backgroundAccent?: string;
                backgroundSubdued?: string;
                borderColor?: string;
                borderColorAccent?: string;
                borderColorSubdued?: string;
                primary?: string;
                primaryBackground?: string;
                primarySubdued?: string;
                primaryAccent?: string;
                secondary?: string;
                secondaryBackground?: string;
                secondarySubdued?: string;
                secondaryAccent?: string;
                success?: string;
                successBackground?: string;
                successSubdued?: string;
                successAccent?: string;
                warning?: string;
                warningBackground?: string;
                warningSubdued?: string;
                warningAccent?: string;
                danger?: string;
                dangerBackground?: string;
                dangerSubdued?: string;
                dangerAccent?: string;
                fonts?: {
                    display?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    sans?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    serif?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    monospace?: {
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
                navigation?: {
                    borderWidth?: string;
                    background?: string;
                    backgroundAccent?: string;
                    borderColor?: string;
                    project?: {
                        borderWidth?: string;
                        foreground?: string;
                        background?: string;
                        borderColor?: string;
                        fontFamily?: string;
                    };
                    modules?: {
                        borderWidth?: string;
                        background?: string;
                        borderColor?: string;
                        button?: {
                            foreground?: string;
                            background?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                            backgroundHover?: string;
                            backgroundActive?: string;
                        };
                    };
                    list?: {
                        foreground?: string;
                        background?: string;
                        fontFamily?: string;
                        foregroundHover?: string;
                        foregroundActive?: string;
                        backgroundHover?: string;
                        backgroundActive?: string;
                        icon?: {
                            foreground?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                        };
                        divider: {
                            borderWidth?: string;
                            borderColor?: string;
                        };
                    };
                };
                header?: {
                    borderWidth?: string;
                    background?: string;
                    borderColor?: string;
                    boxShadow?: string;
                    headline?: {
                        foreground?: string;
                        fontFamily?: string;
                    };
                    title?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
                form?: {
                    columnGap?: string;
                    rowGap?: string;
                    field?: {
                        label?: {
                            foreground?: string;
                            fontFamily?: string;
                            fontWeight?: string;
                        };
                        input?: {
                            foreground?: string;
                            foregroundSubdued?: string;
                            background?: string;
                            backgroundSubdued?: string;
                            borderColor?: string;
                            boxShadow?: string;
                            borderColorHover?: string;
                            borderColorFocus?: string;
                            boxShadowHover?: string;
                            boxShadowFocus?: string;
                            height?: string;
                            padding?: string;
                        };
                    };
                };
                sidebar?: {
                    borderWidth?: string;
                    foreground?: string;
                    background?: string;
                    borderColor?: string;
                    fontFamily?: string;
                    section?: {
                        form?: {
                            columnGap?: string;
                            rowGap?: string;
                            field?: {
                                label?: {
                                    foreground?: string;
                                    fontFamily?: string;
                                    fontWeight?: string;
                                };
                                input?: {
                                    foreground?: string;
                                    foregroundSubdued?: string;
                                    background?: string;
                                    backgroundSubdued?: string;
                                    borderColor?: string;
                                    boxShadow?: string;
                                    borderColorHover?: string;
                                    borderColorFocus?: string;
                                    boxShadowHover?: string;
                                    boxShadowFocus?: string;
                                    height?: string;
                                    padding?: string;
                                };
                            };
                        };
                        toggle?: {
                            borderWidth?: string;
                            foreground?: string;
                            background?: string;
                            borderColor?: string;
                            fontFamily?: string;
                            foregroundHover?: string;
                            foregroundActive?: string;
                            backgroundHover?: string;
                            backgroundActive?: string;
                            icon?: {
                                foreground?: string;
                                foregroundHover?: string;
                                foregroundActive?: string;
                            };
                        };
                    };
                };
                public?: {
                    foreground?: string;
                    foregroundAccent?: string;
                    background?: string;
                    form?: {
                        columnGap?: string;
                        rowGap?: string;
                        field?: {
                            label?: {
                                foreground?: string;
                                fontFamily?: string;
                                fontWeight?: string;
                            };
                            input?: {
                                foreground?: string;
                                foregroundSubdued?: string;
                                background?: string;
                                backgroundSubdued?: string;
                                borderColor?: string;
                                boxShadow?: string;
                                borderColorHover?: string;
                                borderColorFocus?: string;
                                boxShadowHover?: string;
                                boxShadowFocus?: string;
                                height?: string;
                                padding?: string;
                            };
                        };
                    };
                    art?: {
                        background?: string;
                        primary?: string;
                        secondary?: string;
                        speed?: string;
                    };
                };
                popover?: {
                    menu?: {
                        borderRadius?: string;
                        background?: string;
                        boxShadow?: string;
                    };
                };
                banner?: {
                    borderRadius?: string;
                    background?: string;
                    headline?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    title?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                    padding?: string;
                    art?: {
                        foreground?: string;
                    };
                    avatar?: {
                        borderRadius?: string;
                        foreground?: string;
                        background?: string;
                    };
                    subtitle?: {
                        foreground?: string;
                        fontFamily?: string;
                        fontWeight?: string;
                    };
                };
            };
        }[];
    };
    registerTheme: (theme: Theme) => void;
}, "registerTheme">>;
