#!/usr/bin/env bash
# PostToolUse hook: flag admin data-layer violations in admin/src/**/*.{ts,tsx,jsx}
# and DS v2 anti-patterns in admin/src/**/*.{tsx,jsx}.
set -euo pipefail

payload="$(cat)"

file_path="$(printf '%s' "$payload" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
[[ -z "$file_path" ]] && exit 0
[[ "$file_path" != *"/admin/src/"*".ts" && "$file_path" != *"/admin/src/"*".tsx" && "$file_path" != *"/admin/src/"*".jsx" ]] && exit 0
[[ ! -f "$file_path" ]] && exit 0

# Data layer (strapi-plugin-dev/fullstack-standards.md): component → hook → service → getFetchClient.
# Test files are exempt: they mock services and getFetchClient.
# With a fullstack-standards config, its own hooks deny the layering violations
# (strapi-admin preset); only the checks it lacks run here.
has_fullstack_config=false
dir="$(dirname "$file_path")"
while [[ "$dir" != "/" && "$dir" != "." ]]; do
  if [[ -f "$dir/.claude/fullstack-standards.json" ]]; then has_fullstack_config=true; break; fi
  dir="$(dirname "$dir")"
done

data_issues=()
case "$file_path" in
  *.test.* | *.spec.* | */__tests__/*) ;;
  *)
    in_service=false; in_hook=false
    [[ "$file_path" == */services/* || "$file_path" == *.service.ts ]] && in_service=true
    [[ "$file_path" == */hooks/* ]] && in_hook=true

    if ! $has_fullstack_config && grep -qE '\buseFetchClient\b' "$file_path"; then
      data_issues+=("• \`useFetchClient\` — data goes through a feature service calling \`getFetchClient()\`; components and hooks never fetch")
    fi
    if ! $has_fullstack_config && ! $in_service && grep -qE '\bgetFetchClient\b' "$file_path"; then
      data_issues+=("• \`getFetchClient\` outside \`features/*/services/\` — only services call the fetch client; move the request into the feature service")
    fi
    if ! $has_fullstack_config && ! $in_hook && grep -qE '\b(useQuery|useMutation|useInfiniteQuery|useSuspenseQuery)\(' "$file_path"; then
      data_issues+=("• \`useQuery\`/\`useMutation\` outside \`features/*/hooks/\` — components call feature hooks only")
    fi
    if grep -qE 'queryKey:[[:space:]]*\[' "$file_path"; then
      data_issues+=("• Inline \`queryKey: [...]\` — build keys with the factory in \`admin/src/lib/query-keys.ts\`")
    fi
    if [[ "$file_path" != */lib/query-client.ts ]] && grep -qE '\bnew QueryClient\(' "$file_path"; then
      data_issues+=("• \`new QueryClient()\` — every provider uses the one shared \`queryClient\` from \`admin/src/lib/query-client.ts\`")
    fi
    ;;
esac

report_data_issues() {
  [[ ${#data_issues[@]} -eq 0 ]] && return 1
  {
    echo "[strapi-plugin-dev] admin data-layer violations in $(basename "$file_path") (see skills/strapi-plugin-dev/fullstack-standards.md):"
    printf '%s\n' "${data_issues[@]}"
  } >&2
}

# The Design System checks below only apply to JSX files.
if [[ "$file_path" == *.ts ]]; then
  report_data_issues && exit 2
  exit 0
fi

issues=()

# Native HTML interactive elements
if grep -qE '<(button|input|select|textarea)(\s|>)' "$file_path"; then
  issues+=("• Native HTML \`<button>/<input>/<select>/<textarea>\` — use Strapi DS v2 components (Button, TextInput, SingleSelect, Textarea)")
fi

# styled-components
if grep -qE "from ['\"]styled-components['\"]" "$file_path"; then
  issues+=("• \`styled-components\` import — use \`Box\`, \`Flex\`, \`Grid\` with spacing/color props instead")
fi

# alert / window.confirm
if grep -qE '\b(alert|window\.confirm)\s*\(' "$file_path"; then
  issues+=("• \`alert()\` / \`window.confirm()\` — use \`useNotification()\` or \`Dialog\` from DS v2")
fi

# Inline style props
if grep -qE 'style=\{\{' "$file_path"; then
  issues+=("• Inline \`style={{...}}\` — use DS spacing/color props on Box/Flex instead")
fi

# Hex color literals
if grep -qE "['\"]#[0-9a-fA-F]{3,8}['\"]" "$file_path"; then
  issues+=("• Hardcoded hex colors — use DS theme colors via props")
fi

# Removed v4 Modal* components (not just deprecated — absent from DS v2.2.4 source)
if grep -qE '\b(ModalLayout|ModalHeader|ModalBody|ModalFooter)\b' "$file_path"; then
  issues+=("• \`ModalLayout/ModalHeader/ModalBody/ModalFooter\` do NOT exist in DS v2 — use the \`Modal.Root/Content/Header/Title/Body/Footer\` compound API")
fi

# Layouts / Page imported from the DS instead of @strapi/strapi/admin
if grep -qE "import[^;]*\b(Layouts|Page)\b[^;]*from ['\"]@strapi/design-system['\"]" "$file_path"; then
  issues+=("• \`Layouts\`/\`Page\` are not exported by \`@strapi/design-system\` — import them from \`@strapi/strapi/admin\`")
fi

# Deprecated Tooltip `description` prop (v2.2.4: @deprecated, use label)
if grep -qE '<Tooltip[^>]*\bdescription=' "$file_path"; then
  issues+=("• \`Tooltip\` \`description\` prop is deprecated in DS v2 — use \`label\` instead")
fi

# Deprecated Th `action` prop (v2.2.4: @deprecated, pass as children)
if grep -qE '<Th[^>]*\baction=' "$file_path"; then
  issues+=("• \`Th\` \`action\` prop is deprecated in DS v2 — pass everything as children instead")
fi

# NumberInput uses onValueChange, not onChange
if grep -qE '<NumberInput[^>]*\bonChange=' "$file_path"; then
  issues+=("• \`NumberInput\` uses \`onValueChange(value: number | undefined)\`, not \`onChange\`")
fi

# Select/Option don't exist in DS v2
if grep -qE "import[^;]*\b(Select|Option)\b[^;]*from ['\"]@strapi/design-system['\"]" "$file_path"; then
  issues+=("• \`Select\`/\`Option\` are not exported by DS v2 — use \`SingleSelect\`/\`SingleSelectOption\` (or \`MultiSelect\`/\`MultiSelectOption\`)")
fi

# Field.Hint / Field.Error take no children — text goes on Field.Root
if grep -qE '<Field\.(Hint|Error)>[^<]' "$file_path"; then
  issues+=("• \`Field.Hint\`/\`Field.Error\` ignore children — pass the text via \`<Field.Root hint=... error=...>\` and render \`<Field.Hint />\`/\`<Field.Error />\`")
fi

# Trigger/Cancel/Action/Close parts always render asChild; the prop is not accepted
if grep -qE '<(Dialog|Modal|Popover)\.(Trigger|Cancel|Action|Close)[^>]*\basChild\b' "$file_path"; then
  issues+=("• \`asChild\` is not accepted on Dialog/Modal/Popover Trigger/Cancel/Action/Close — they already render as their child")
fi

# Toggle is an input: onChange + required onLabel/offLabel (Switch has onCheckedChange)
if grep -qE '<Toggle[^>]*\bonCheckedChange=' "$file_path"; then
  issues+=("• \`Toggle\` has no \`onCheckedChange\` — use \`onChange={(e) => ...e.target.checked}\` with \`onLabel\`/\`offLabel\`, or use \`Switch\`")
fi

# Icons that don't exist in @strapi/icons v2
if grep -qE "import[^;]*\b(ExclamationMarkCircle|Refresh|Puzzle|EmptyDocuments)\b[^;]*from ['\"]@strapi/icons['\"]" "$file_path"; then
  issues+=("• Icon not in \`@strapi/icons\` v2 — use \`WarningCircle\`, \`ArrowClockwise\`, \`PuzzlePiece\`; \`EmptyDocuments\` comes from \`@strapi/icons/symbols\`")
fi

# Path imports from @strapi/design-system
if grep -qE "from ['\"]@strapi/design-system/[A-Za-z]" "$file_path"; then
  issues+=("• Path imports from \`@strapi/design-system/...\` — use root imports: \`from '@strapi/design-system'\`")
fi

found=false
report_data_issues && found=true

if [[ ${#issues[@]} -gt 0 ]]; then
  {
    echo "[strapi-ui-design] DS v2 anti-patterns in $(basename "$file_path"):"
    printf '%s\n' "${issues[@]}"
  } >&2
  found=true
fi

$found && exit 2
exit 0
