[
  .[][]
  | select(.draft == false and .prerelease == false and .tag_name != $current)
  | {
      published_at,
      asset: ([.assets[] | select(.name == $name)] | first)
    }
  | select(.asset != null)
]
| sort_by(.published_at)
| last
| .asset.url // ""
