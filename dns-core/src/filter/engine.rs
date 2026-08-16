use crate::filter::trie::DomainTrie;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FilterResult {
    Allowed,
    AllowListMatched(String),
    Blocked(String),
}

#[derive(Debug, Default)]
pub struct FilterEngine {
    allowlist: DomainTrie,
    blocklist: DomainTrie,
}

impl FilterEngine {
    pub fn new() -> Self {
        Self {
            allowlist: DomainTrie::new(),
            blocklist: DomainTrie::new(),
        }
    }

    pub fn load_allowlist_rule(&mut self, rule: &str) {
        let clean = rule.trim_start_matches("@@");
        self.allowlist.insert_rule(clean);
    }

    pub fn load_blocklist_rule(&mut self, rule: &str) {
        self.blocklist.insert_rule(rule);
    }

    pub fn load_blocklist_content(&mut self, content: &str) -> usize {
        let mut count = 0;
        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("@@") {
                self.load_allowlist_rule(trimmed);
            } else if !trimmed.is_empty() && !trimmed.starts_with('#') && !trimmed.starts_with('!') {
                self.load_blocklist_rule(trimmed);
                count += 1;
            }
        }
        count
    }

    /// Evaluates a queried domain:
    /// 1. Check AllowList (overrides blocklist) -> Allowed if matched
    /// 2. Check BlockList (with parent domain matching) -> Blocked if matched
    /// 3. Otherwise Allowed
    pub fn evaluate(&self, domain: &str) -> FilterResult {
        let normalized = DomainTrie::normalize(domain);

        if self.allowlist.matches(&normalized) {
            return FilterResult::AllowListMatched(normalized);
        }

        if self.blocklist.matches(&normalized) {
            return FilterResult::Blocked(normalized);
        }

        FilterResult::Allowed
    }

    /// Load allowlist rules from file content (one rule per line; @@ prefix optional).
    pub fn load_allowlist_content(&mut self, content: &str) -> usize {
        let mut count = 0;
        for line in content.lines() {
            let trimmed = line.trim();
            if !trimmed.is_empty() && !trimmed.starts_with('#') && !trimmed.starts_with('!') {
                self.load_allowlist_rule(trimmed);
                count += 1;
            }
        }
        count
    }

    pub fn blocklist_rule_count(&self) -> usize {
        self.blocklist.len()
    }

    pub fn allowlist_rule_count(&self) -> usize {
        self.allowlist.len()
    }
}
