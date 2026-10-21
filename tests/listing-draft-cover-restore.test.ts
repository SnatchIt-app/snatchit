/**
 * tests/listing-draft-cover-restore.test.ts — CFT-608: putting a draft's cover back into the
 * REAL useImageUpload hook.
 *
 * `restore(uri)` is additive: the transfer-send screen (C's) is the hook's other consumer and does
 * not call it. A restored cover behaves as a fresh pick of that file — a new object name, no upload
 * record carried over from anything earlier — so publish uploads it exactly once, under the F-IMG-1
 * rules (upsert:false, the bytes decide the type). Nothing here uploads or deletes at restore time.
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { HookHost, REPO_ROOT } from './helpers/nav-stack-harness';

const h = vi.hoisted(() => {
  const deferred = <T,>() => {
    let resolve!: (v: T) => void;
    const promise = new Promise<T>((r) => { resolve = r; });
    return { promise, resolve };
  };
  return {
    deferred,
    launches: [] as ReturnType<typeof deferred<unknown>>[],
    uploads: [] as { bucket: string; path: string; upsert: unknown; contentType: unknown }[],
    fetched: [] as string[],
    removes: 0,
  };
});

vi.mock('expo-image-picker', () => ({
  requestMediaLibraryPermissionsAsync: async () => ({ status: 'granted', canAskAgain: true }),
  launchImageLibraryAsync: () => { const d = h.deferred<unknown>(); h.launches.push(d); return d.promise; },
  UIImagePickerPreferredAssetRepresentationMode: { Compatible: 'compatible' },
}));
vi.mock('react-native', () => ({ Alert: { alert: () => {} }, Linking: { openSettings: async () => {} } }));
vi.mock('@/src/lib/media/url', () => ({ IMMUTABLE_CACHE_CONTROL: 'max-age=31536000, immutable' }));
vi.mock('@/src/utils/validateImage', () => ({ validateImage: () => ({ valid: true }) }));
vi.mock('@/src/lib/supabase', () => ({
  supabase: {
    storage: {
      from: (bucket: string) => ({
        upload: async (path: string, _b: Uint8Array, o: { upsert?: unknown; contentType?: unknown }) => {
          h.uploads.push({ bucket, path, upsert: o.upsert, contentType: o.contentType });
          return { data: { path }, error: null };
        },
        exists: async () => ({ data: false, error: null }),
        remove: async () => { h.removes += 1; return { data: [], error: null }; },
        getPublicUrl: (path: string) => ({ data: { publicUrl: `https://cdn.test/${path}` } }),
      }),
    },
  },
}));

const COVER = 'file:///var/mobile/Containers/Data/Application/0A1B/Library/Caches/ImagePicker/5E6F.jpeg';
const OTHER = 'file:///var/mobile/Containers/Data/Application/0A1B/Library/Caches/ImagePicker/9999.jpeg';
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46, 0x49, 0x46, 0, 1]);

type Ret = {
  localUri: string | null; storagePath: string | null; status: string; error: string | null;
  pickImage(): Promise<void>; uploadImage(): Promise<string | null>; reset(): void; restore(uri: string): void;
};

const settle = async () => { for (let i = 0; i < 8; i++) await new Promise((r) => setImmediate(r)); };

async function mountUpload() {
  const { useImageUpload } = await import('@/src/hooks/useImageUpload');
  const state: { ret: Ret | null } = { ret: null };
  const host = new HookHost(() => {
    state.ret = useImageUpload({ userId: 'u-1', folder: 'covers', aspect: null, quality: 0.85 }) as unknown as Ret;
    return null;
  }, new Map());
  host.mount();
  return { host, state };
}

const realFetch = globalThis.fetch;
beforeEach(() => {
  vi.resetModules();
  h.launches.length = 0; h.uploads.length = 0; h.fetched.length = 0; h.removes = 0;
  globalThis.fetch = (async (uri: string) => { h.fetched.push(uri); return { arrayBuffer: async () => JPEG.buffer.slice(0) }; }) as unknown as typeof fetch;
});
afterEach(() => { globalThis.fetch = realFetch; vi.useRealTimers(); });

describe('CR · restoring a draft cover into the upload hook', () => {
  it('CR1: restore selects the file as a fresh pick — ready, no error, nothing uploaded yet', async () => {
    const { host, state } = await mountUpload();
    state.ret!.restore(COVER);
    host.flush();
    expect(state.ret!.localUri).toBe(COVER);
    expect(state.ret!.status).toBe('ready');
    expect(state.ret!.error).toBeNull();
    expect(state.ret!.storagePath).toBeNull();
    expect(h.uploads).toEqual([]);
    expect(h.fetched).toEqual([]);
  });

  it('CR2: publish uploads the restored file once, under a new object name, never overwriting', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(2026, 9, 21, 12, 0, 0));
    const { host, state } = await mountUpload();
    state.ret!.restore(COVER);
    host.flush();
    const path = await state.ret!.uploadImage();
    host.flush();
    expect(h.fetched).toEqual([COVER]);
    expect(h.uploads).toEqual([{ bucket: 'auction-media', path: `u-1/covers/${Date.now()}.jpg`, upsert: false, contentType: 'image/jpeg' }]);
    expect(path).toBe(`u-1/covers/${Date.now()}.jpg`);
    expect(state.ret!.status).toBe('done');
  });

  it('CR3: restoring over an uploaded selection forgets that upload — a different file is never given the old object', async () => {
    const { host, state } = await mountUpload();
    state.ret!.restore(OTHER);
    host.flush();
    await state.ret!.uploadImage();
    host.flush();
    expect(state.ret!.storagePath).not.toBeNull();
    state.ret!.restore(COVER);
    host.flush();
    expect(state.ret!.storagePath).toBeNull();
    expect(state.ret!.status).toBe('ready');
    await state.ret!.uploadImage();
    expect(h.uploads).toHaveLength(2);
    expect(h.fetched).toEqual([OTHER, COVER]);
  });

  it('CR4: a restore while the picker is open is ignored — the seller’s pick wins', async () => {
    const { host, state } = await mountUpload();
    const picking = state.ret!.pickImage();
    await settle();
    host.flush();
    expect(state.ret!.status).toBe('picking');
    state.ret!.restore(COVER);
    host.flush();
    h.launches[0].resolve({ canceled: false, assets: [{ uri: OTHER, mimeType: 'image/jpeg', fileSize: 10 }] });
    await picking;
    host.flush();
    expect(state.ret!.localUri).toBe(OTHER);
  });

  it('CR5: restore deletes nothing and the transfer-send consumer does not call it', async () => {
    const { host, state } = await mountUpload();
    state.ret!.restore(COVER);
    host.flush();
    state.ret!.reset();
    host.flush();
    expect(h.removes).toBe(0);
    const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
    const hook = strip(readFileSync(join(REPO_ROOT, 'src/hooks/useImageUpload.ts'), 'utf8'));
    expect(hook).not.toMatch(/\.remove\(/);
    const send = strip(readFileSync(join(REPO_ROOT, 'app/transfer/send/[id].tsx'), 'utf8'));
    expect(send).not.toMatch(/\.restore\(/);
  });
});
