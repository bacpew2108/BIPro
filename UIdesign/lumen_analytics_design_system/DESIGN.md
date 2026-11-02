---
name: Lumen Analytics Design System
colors:
  surface: '#fcf8fb'
  surface-dim: '#dcd9dc'
  surface-bright: '#fcf8fb'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f6f3f5'
  surface-container: '#f0edef'
  surface-container-high: '#eae7ea'
  surface-container-highest: '#e4e2e4'
  on-surface: '#1b1b1d'
  on-surface-variant: '#414754'
  inverse-surface: '#303032'
  inverse-on-surface: '#f3f0f2'
  outline: '#717786'
  outline-variant: '#c0c6d6'
  surface-tint: '#005db8'
  primary: '#005ab3'
  on-primary: '#ffffff'
  primary-container: '#0073e0'
  on-primary-container: '#fefcff'
  inverse-primary: '#aac7ff'
  secondary: '#4a47d2'
  on-secondary: '#ffffff'
  secondary-container: '#6462ec'
  on-secondary-container: '#fffbff'
  tertiary: '#9a4100'
  on-tertiary: '#ffffff'
  tertiary-container: '#c25300'
  on-tertiary-container: '#fffbff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d6e3ff'
  primary-fixed-dim: '#aac7ff'
  on-primary-fixed: '#001b3e'
  on-primary-fixed-variant: '#00468d'
  secondary-fixed: '#e2dfff'
  secondary-fixed-dim: '#c2c1ff'
  on-secondary-fixed: '#0c006b'
  on-secondary-fixed-variant: '#332dbc'
  tertiary-fixed: '#ffdbcb'
  tertiary-fixed-dim: '#ffb691'
  on-tertiary-fixed: '#341100'
  on-tertiary-fixed-variant: '#793100'
  background: '#fcf8fb'
  on-background: '#1b1b1d'
  surface-variant: '#e4e2e4'
typography:
  display:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 34px
    letterSpacing: -0.018em
  headline-lg:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 26px
    letterSpacing: -0.015em
  headline-md:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '600'
    lineHeight: 18px
    letterSpacing: -0.006em
  body-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: -0.005em
  body-md:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
    letterSpacing: -0.003em
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
    letterSpacing: 0em
  label-md:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Inter
    fontSize: 10px
    fontWeight: '500'
    lineHeight: 13px
    letterSpacing: 0.02em
  metric-display:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 28px
    letterSpacing: -0.02em
  data-mono:
    fontFamily: JetBrains Mono
    fontSize: 11px
    fontWeight: '400'
    lineHeight: 15px
    letterSpacing: 0em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 12px
  margin: 16px
  space-xs: 4px
  space-sm: 8px
  space-md: 12px
  space-lg: 16px
  space-xl: 24px
---

## Brand & Style

This design system translates the native craft of macOS Sequoia into an enterprise-grade business intelligence and visual analytics workstation. Built for quantitative analysts, data architects, and executive leaders, the interface balances dense analytical workflows with the optical precision, weightless materiality, and restrained ergonomics expected of a tier-one macOS desktop application.

The design movement combines **Modern HIG-Inspired Materiality** with **Technical Precision Minimalist Glassmorphism**. The visual hierarchy relies on layered translucent materials (vibrancy, material blurs, fine hairpins), micro-typography, and high-density information layout inspired by professional productivity suites like Power BI, Xcode, and Numbers. The emotional response is immediate clarity, architectural stability, and frictionless analytical momentum.

## Colors

The palette reproduces the native desktop color hierarchy of macOS Sequoia light mode. Color is deployed strictly as semantic data indicator or focal accent; chrome surfaces remain achromatic and reflective.

- **Primary Accent (`#0A84FF`)**: Native macOS system blue. Reserved for interactive selection states, active segmented items, primary actions, focused search anchors, and primary metric emphasis.
- **Secondary Accent (`#5E5CE6`)**: Native macOS system indigo. Utilized for secondary analytical series, comparative benchmark overlays, and auxiliary data tags.
- **Window Backdrop (`#EBEBF0`)**: The low-tier desktop foundation under the report canvas, providing natural contrast against pure white analytics tiles.
- **Secondary Chrome (`#F5F5F7`)**: The default background for toolbars, inspector panes, column headers, and native sidebars.
- **Canvas Base (`#FFFFFF`)**: Pure white surface reserved for the analytical viewport, report canvas, visual cards, and popover content.
- **Subtle Neutral Separator (`#E5E5EA`)**: Strict hairline border token separating sidebars, tool ribbons, docked inspector panels, and table cells.
- **Text & Hierarchy**:
  - Primary Label: `#1C1C1E` (system primary text)
  - Secondary Label: `#636366` (subheadings, metadata, inactive icons)
  - Tertiary Label: `#8E8E93` (placeholders, axis labels, disabled markers)
- **Data Series Palette**: A cohesive, color-safe 6-hue analytical ramp: Blue (`#0A84FF`), Indigo (`#5E5CE6`), Teal (`#30B0C7`), Mint (`#34C759`), Amber (`#FF9F0A`), and Coral (`#FF453A`).

## Typography

The type system prioritizes Apple’s SF Pro system font metrics (modeled with Inter and JetBrains Mono for monospaced values). Micro-typographic clarity is mandatory: dense numeric matrices, DAX formulas, calculation models, and metric visualizers demand strict vertical rhythm and proportional spacing.

- Apply `data-mono` strictly for tabular data rows, financial ledger balances, formula code bars, and SQL/DAX query inputs.
- Enable OpenType tabular numbers (`tnum`) across all standard body styles presenting numeric metrics or coordinate fields.
- Reserve `metric-display` for KPI visualizer callouts within report tiles.
- Use `label-sm` with slight positive tracking for all-caps inspector section headers, axis captions, and secondary field metadata.

## Layout & Spacing

The layout adheres to a multi-pane native desktop shell architecture structured into five synchronized zones:
1. **Unified macOS Title Bar / Toolbar (52px fixed height)**: Houses macOS traffic lights (close, minimize, zoom) on the left margin, title and breadcrumb navigation centered, and workspace mode toggles + global share tools on the right.
2. **Left Navigation / Data Model Sidebar (240px default, resizable 200px–360px)**: Collapsible hierarchy containing data sources, table relationships, field lists, and report pages.
3. **Primary Canvas Viewport (Fluid)**: Positioned on the `#EBEBF0` desktop backdrop. The interactive report canvas sits nested with a 16px inset margin, utilizing snap-to-grid layout guidelines (8px base increments).
4. **Docked Visualizations & Fields Inspector (280px default, resizable on the right)**: Houses visualization pickers, field wells (Axis, Legend, Values, Tooltips), and visual formatting properties.
5. **Contextual Formula & Filter Bar (32px fixed height)**: Sits below the title bar with quick filters, breadcrumb slices, and formula definitions.

Spacing tokens dictate tight, compact analytical density. Padding inside form inputs, list rows, and table headers adheres to a compact 4px–8px vertical rhythm.

## Elevation & Depth

Visual depth is achieved through native macOS vibrancy and crisp boundary definition rather than aggressive drop shadows.

- **Vibrancy & Materiality**:
  - Sidebars and toolbars implement translucent blur: `backdrop-filter: blur(20px) saturate(180%)` backed by `rgba(245, 245, 247, 0.85)`.
  - Floating modal windows and popover inspectors utilize heavy material blur: `backdrop-filter: blur(30px) saturate(190%)` backed by `rgba(255, 255, 255, 0.90)`.
- **Low-Contrast Structural Borders**:
  - Windows, panels, segmented controls, and visual cards are delimited by 1px solid `#E5E5EA` borders.
  - Floating dialogs use a composite hairline border: `1px solid rgba(0, 0, 0, 0.08)`.
- **Shadow Levels**:
  - **Tile / Card Elevation**: `0 1px 2px rgba(0, 0, 0, 0.04), 0 0 0 1px rgba(0, 0, 0, 0.05)`.
  - **Active Drag / Selected Visual Tile**: `0 8px 20px rgba(0, 0, 0, 0.08), 0 0 0 1.5px #0A84FF`.
  - **Popovers & Dropdowns**: `0 10px 24px -4px rgba(0, 0, 0, 0.12), 0 2px 6px rgba(0, 0, 0, 0.06), 0 0 0 0.5px rgba(0, 0, 0, 0.08)`.

## Shapes

The interface embraces the standard macOS 8px geometric squircle standard (`0.5rem`). This radius gives data visualization containers, dialogue cards, and control panels an organic yet structurally disciplined container silhouette.

- **Report Visual Tiles & Canvas Cards**: Standard 8px radius (`0.5rem`).
- **Toolbar Buttons, Input Fields, Menus**: 6px radius (`0.375rem`) for compact UI ergonomics.
- **Segmented Control Containers & Sliders**: 6px outer radius with 5px inner tab indicator.
- **Traffic Light Window Buttons**: Pure circles (12px diameter, 8px spacing, centered at 14px left margin).
- **Tooltips & Status Badges**: 4px radius for tight spatial discipline.

## Components

### Window Chrome & Traffic Lights
- **Window Controls**: Top-left inset 14px from left, 14px from top. Diameter 12px.
  - Close: `#FF5F57` (border `#E0443E`)
  - Minimize: `#FEBC2E` (border `#D89E24`)
  - Zoom: `#28C840` (border `#1AAB29`)
- Unified title bar height: 52px, rendered with translucent material and hairline border-bottom (`#E5E5EA`).

### Buttons
- **Primary Push Button**: Background `#0A84FF`, label `#FFFFFF`, font-weight 500, radius 6px, height 26px (compact) or 30px (standard). Hover state: `#0077ED`. Active state: `#0068D6`.
- **Secondary / Standard Push Button**: Background `#FFFFFF`, border `1px solid #E5E5EA`, text `#1C1C1E`, box-shadow `0 0.5px 1px rgba(0, 0, 0, 0.05)`. Hover: `#F5F5F7`.
- **Icon / Ghost Tool Button**: 26px × 26px square, radius 5px, no border. Hover: `rgba(0, 0, 0, 0.04)`. Pressed: `rgba(0, 0, 0, 0.08)`.

### Segmented Controls (macOS Native Pill Switchers)
- Container: Background `rgba(118, 118, 128, 0.12)`, padding 2px, radius 7px.
- Selected Segment: Background `#FFFFFF`, radius 5px, box-shadow `0 1px 3px rgba(0, 0, 0, 0.12), 0 0.5px 1px rgba(0, 0, 0, 0.08)`, text `#1C1C1E`, font-weight 500.
- Unselected Segment: Text `#636366`, transparent background, hover text `#1C1C1E`.

### Visual Cards (Report Tiles)
- Surface: `#FFFFFF` fill, 8px corner radius, hairline border `1px solid #E5E5EA`.
- Header: 36px height with title (`headline-sm`), contextual icon menu on hover, and subtitle/filter badge indicator.
- Selection State: Outline `1.5px solid #0A84FF` with subtle resize anchor handles at bounding corners.

### Lists, Tree Views & Field Wells
- Data Tree View: Indented 12px per hierarchy node with SF Symbol disclosures (`chevron.right`, `chevron.down` at 10px).
- Row Height: 24px compact table/field rows; 28px standard navigation rows.
- Selection Highlight: Active full-bleed rounded row highlight using `#0A84FF` with white text, or subtle macOS secondary selection `#E5E5EA` with `#1C1C1E` text when window loses focus.

### Inputs & Search Bars
- Search Field: Native search field with leading magnifying glass icon, height 28px, background `rgba(118, 118, 128, 0.08)`, border `0.5px solid transparent`, radius 6px. Focused state: `#FFFFFF` fill with `1.5px solid #0A84FF` focus ring.

### Checkboxes, Switches & Radio Controls
- Checkbox: 14px × 14px, 3.5px corner radius. Inactive: border `1px solid #C7C7CC`, background `#FFFFFF`. Active: `#0A84FF` fill with white checkmark icon.
- Native Toggle Switch: Width 36px, height 20px, radius 10px. Active track `#34C759`, thumb white circle (16px) with soft ambient drop shadow.

### Chips & Filter Pills
- Filter Slicers: Height 22px, background `#F5F5F7`, border `1px solid #E5E5EA`, radius 4px, font size 11px, text `#1C1C1E`. Dismiss cross icon on right trailing edge.