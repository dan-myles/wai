// Files imported as text (the skill) or embedded as files (addon assets, see scripts/build.ts).
declare module "*.md" {
  const text: string
  export default text
}
declare module "*.lua" {
  const path: string
  export default path
}
declare module "*.toc" {
  const path: string
  export default path
}
declare module "*.xml" {
  const path: string
  export default path
}
declare module "*.ttf" {
  const path: string
  export default path
}
declare module "*.tga" {
  const path: string
  export default path
}
