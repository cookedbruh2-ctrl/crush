// Performance & Optimization utilities for crush
import { writable } from 'svelte/store';

export interface PerfSettings {
  enableVSync: boolean;
  targetFPS: number;
  lowPowerMode: boolean;
  hardwareAccel: boolean;
  cacheSizeMB: number;
}

export const perfStore = writable<PerfSettings>({
  enableVSync: true,
  targetFPS: 60,
  lowPowerMode: false,
  hardwareAccel: true,
  cacheSizeMB: 256,
});

export function applyPerformanceOptimizations(settings: PerfSettings) {
  // Apply to Tauri window
  if (typeof window !== 'undefined' && (window as any).__TAURI__) {
    // Future: call native performance plugin
    console.log('[crush] Applying performance settings:', settings);
  }

  // CSS-level perf tweaks
  const root = document.documentElement;
  root.style.setProperty('--target-fps', String(settings.targetFPS));

  if (settings.lowPowerMode) {
    root.classList.add('low-power');
  } else {
    root.classList.remove('low-power');
  }
}

export async function optimizeMemory() {
  if ('gc' in window) {
    (window as any).gc();
  }
  // Clear theme cache etc.
  console.log('[crush] Memory optimization triggered');
}
