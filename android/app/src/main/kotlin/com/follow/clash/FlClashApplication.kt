package com.follow.clash

import androidx.multidex.MultiDexApplication
import android.content.Context
import com.follow.clash.common.GlobalState

class FlClashApplication : MultiDexApplication() {
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        GlobalState.init(this)
    }
}
