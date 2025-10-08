import { Render } from '@measured/puck';
import { config } from '@/lib/puck/config';
import { loadData } from '@/lib/puck/store';

/**
 * Dashboard page
 *
 * This page renders the content saved by the Puck editor.  It uses
 * the "dashboard" identifier to locate data files in the store.  When
 * no data exists the component renders nothing.
 */
export default async function Dashboard() {
  const data = await loadData('dashboard');
  return <Render config={config} data={data ?? {}} />;
}