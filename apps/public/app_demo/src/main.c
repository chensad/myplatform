#include <stdio.h>

int main(void)
{
    printf("app_demo: platform skeleton is alive\n");
    printf("  model: imx6ull_100ask_pro=%d\n",
#ifdef CONFIG_MODEL_IMX6ULL_100ASK_PRO
           1
#else
           0
#endif
    );
    printf("  feature wifi=%d qt=%d lvgl=%d modem=%d\n",
#ifdef CONFIG_FEATURE_WIFI
           CONFIG_FEATURE_WIFI,
#else
           0,
#endif
#ifdef CONFIG_FEATURE_QT
           CONFIG_FEATURE_QT,
#else
           0,
#endif
#ifdef CONFIG_FEATURE_LVGL
           CONFIG_FEATURE_LVGL,
#else
           0,
#endif
#ifdef CONFIG_FEATURE_MODEM
           CONFIG_FEATURE_MODEM
#else
           0
#endif
    );
    return 0;
}
