/** Exit ids a layout offers (`properties.kind === 'exit'`). */
export function layoutExitIds(layout) {
  const feats = layout?.geojson?.features ?? [];
  return feats.filter((f) => f?.properties?.kind === 'exit').map((f) => String(f.properties.id));
}

/** True when [exitId] is null/undefined (clear the choice) or names an exit that exists in [layout]. */
export function isValidEvacExit(layout, exitId) {
  if (exitId === null || exitId === undefined) return true;
  return layoutExitIds(layout).includes(String(exitId));
}
