import type { Config } from '@measured/puck';

/**
 * Configuration for the Puck editor.  Define reusable UI blocks and their
 * editable fields here.  You can add your own components to build custom
 * dashboards and pages.
 */
export const config: Config = {
  components: {
    /**
     * A simple statistic card with a title and numeric value.
     */
    StatCard: {
      fields: {
        title: { type: 'text', defaultValue: 'Untitled Stat' },
        value: { type: 'number', defaultValue: 0 },
      },
      render: ({ title, value }) => (
        <div style={{ padding: '1rem', border: '1px solid #ccc', borderRadius: '4px' }}>
          <strong>{title}</strong>
          <p>{value}</p>
        </div>
      ),
    },
    /**
     * A grid layout that arranges children into equal columns.
     */
    Grid: {
      fields: {
        columns: { type: 'number', defaultValue: 2 },
        children: { type: 'children' },
      },
      render: ({ columns, children }) => (
        <div style={{ display: 'grid', gridTemplateColumns: `repeat(${columns}, 1fr)`, gap: '1rem' }}>
          {children}
        </div>
      ),
    },
    /**
     * A markdown block.  The editor stores the raw markdown; rendering is
     * delegated to the browser using `dangerouslySetInnerHTML`.  This is
     * intentionally simple; for production use integrate a proper markdown
     * renderer.
     */
    Markdown: {
      fields: {
        content: { type: 'textarea', defaultValue: '# Hello world' },
      },
      render: ({ content }) => (
        <div dangerouslySetInnerHTML={{ __html: content }} />
      ),
    },
  },
};