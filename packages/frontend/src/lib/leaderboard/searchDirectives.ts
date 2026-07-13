/**
 * Parses search directives from a leaderboard search string.
 *
 * Supported directives:
 * - `client:<value>` — filter users who have submitted data from this client
 * - `model:<value>` — filter users who have used this model
 *
 * Directives are case-insensitive and can appear anywhere in the search string.
 * Multiple directives of the same type are OR-ed (user matches if ANY applies).
 * Remaining non-directive text is treated as a username/displayName search term.
 *
 * Examples:
 *   "client:opencode junhoyeo"  → { clients: ["opencode"], models: [], text: "junhoyeo" }
 *   "model:claude-sonnet-4"    → { clients: [], models: ["claude-sonnet-4"], text: "" }
 *   "client:claude client:amp" → { clients: ["claude", "amp"], models: [], text: "" }
 */

export interface ParsedSearchDirectives {
  /** Free-text portion (username/displayName search). Trimmed. */
  text: string;
  /** Client IDs extracted from `client:` directives. Lowercased. */
  clients: string[];
  /** Model IDs extracted from `model:` directives. Lowercased. */
  models: string[];
}

const DIRECTIVE_REGEX = /\b(client|model):(\S+)/gi;

export function parseSearchDirectives(raw: string): ParsedSearchDirectives {
  const clients: string[] = [];
  const models: string[] = [];

  // Extract directives and collect the remaining text
  const text = raw
    .replace(DIRECTIVE_REGEX, (_, directive: string, value: string) => {
      const lowerDirective = directive.toLowerCase();
      const lowerValue = value.toLowerCase();

      if (lowerDirective === "client") {
        clients.push(lowerValue);
      } else if (lowerDirective === "model") {
        models.push(lowerValue);
      }

      return "";
    })
    .replace(/\s+/g, " ")
    .trim();

  return { text, clients, models };
}

/**
 * Returns true if the parsed directives contain any filtering constraints
 * (i.e. at least one client or model directive was specified).
 */
export function hasDirectives(parsed: ParsedSearchDirectives): boolean {
  return parsed.clients.length > 0 || parsed.models.length > 0;
}
