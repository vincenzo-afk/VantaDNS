use ahash::AHashSet;

#[derive(Debug, Default, Clone)]
pub struct DomainTrie {
    exact_matches: AHashSet<String>,
    wildcard_matches: AHashSet<String>,
}

impl DomainTrie {
    pub fn new() -> Self {
        Self {
            exact_matches: AHashSet::new(),
            wildcard_matches: AHashSet::new(),
        }
    }

    /// Normalizes a domain name (lowercase, trim whitespace & trailing dot)
    pub fn normalize(domain: &str) -> String {
        domain.trim().trim_end_matches('.').to_lowercase()
    }

    /// Inserts a domain or rule into the lookup structure
    /// Supports standard hosts format (`0.0.0.0 ad.com`), raw domains (`ad.com`), or AdGuard rules (`||ad.com^`)
    pub fn insert_rule(&mut self, raw_rule: &str) {
        let trimmed = raw_rule.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') || trimmed.starts_with('!') {
            return;
        }

        let rule = if trimmed.starts_with("||") {
            trimmed.trim_start_matches("||").trim_end_matches('^')
        } else if trimmed.starts_with("0.0.0.0 ") || trimmed.starts_with("127.0.0.1 ") {
            trimmed.split_whitespace().nth(1).unwrap_or("")
        } else {
            trimmed
        };

        let normalized = Self::normalize(rule);
        if normalized.is_empty() {
            return;
        }

        self.wildcard_matches.insert(normalized.clone());
        self.exact_matches.insert(normalized);
    }

    /// Checks if a domain matches any loaded rule (either exact match or parent-domain match)
    pub fn matches(&self, domain: &str) -> bool {
        let normalized = Self::normalize(domain);
        if self.exact_matches.contains(&normalized) {
            return true;
        }

        // Parent domain iteration: "a.b.example.com" -> check "b.example.com" -> check "example.com"
        let mut current = normalized.as_str();
        while let Some(dot_idx) = current.find('.') {
            current = &current[dot_idx + 1..];
            if self.wildcard_matches.contains(current) {
                return true;
            }
        }

        false
    }

    pub fn len(&self) -> usize {
        self.exact_matches.len()
    }

    pub fn is_empty(&self) -> bool {
        self.exact_matches.is_empty()
    }
}
