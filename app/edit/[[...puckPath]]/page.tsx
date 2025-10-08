'use client';

import { useMemo } from 'react';
import { Puck } from '@measured/puck';
import { config } from '@/lib/puck/config';
import { loadData, saveData } from '@/lib/puck/store';

/**
 * Puck editor page
 *
 * This page hosts the Puck editor for editing any page in your site.  The
 * catch‑all route parameter (`puckPath`) determines which JSON file is loaded
 * and saved.  When no path is provided the editor defaults to "dashboard".
 */
export default function EditPage({ params }: { params: { puckPath?: string[] } }) {
  const id = useMemo(() => {
    if (!params?.puckPath || params.puckPath.length === 0) return 'dashboard';
    return params.puckPath.join('/');
  }, [params]);

  const data = loadData(id);

  return (
    <Puck
      config={config}
      data={data ?? {}}
      onPublish={(d) => saveData(id, d)}
    />
  );
}