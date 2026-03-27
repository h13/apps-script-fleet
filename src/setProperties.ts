/**
 * Set script properties via clasp run.
 * Called from CI/CD to inject environment-specific configuration.
 *
 * @param props - Key-value pairs to set as script properties
 * @returns The properties that were set (for confirmation)
 */
export function setScriptProperties(
  props: Record<string, string>,
): Record<string, string> {
  PropertiesService.getScriptProperties().setProperties(props, false);
  return props;
}
