// Tweetintosh: Ultra-lightweight macOS X Client - DOM Inject Script

(function() {
    'use strict';

    // 1. Send unread count updates to macOS Dock
    let lastBadgeCount = -1;

    function updateDockBadge() {
        // Extract unread count from document.title, e.g. "(3) Home / X" or "(12) Notifications / X"
        const titleMatch = document.title.match(/^\((\d+)\)/);
        let count = titleMatch ? parseInt(titleMatch[1], 10) : 0;

        // Also check notification badge counter element in sidebar
        if (count === 0) {
            const badgeEl = document.querySelector('a[href="/notifications"] div[aria-label*="unread"], a[href="/notifications"] div[aria-label*="未读"]');
            if (badgeEl) {
                const text = badgeEl.textContent.trim();
                const parsed = parseInt(text, 10);
                if (!isNaN(parsed) && parsed > 0) {
                    count = parsed;
                }
            }
        }

        if (count !== lastBadgeCount) {
            lastBadgeCount = count;
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.notificationBadge) {
                window.webkit.messageHandlers.notificationBadge.postMessage(count);
            }
        }
    }

    // 2. Clean promoted tweets & intrusive elements dynamically
    function purgePromotedTweets() {
        const tweets = document.querySelectorAll('article[data-testid="tweet"]');
        for (let i = 0; i < tweets.length; i++) {
            const tweet = tweets[i];
            if (tweet.dataset.maxChecked) continue;
            tweet.dataset.maxChecked = "true";

            // Check if tweet contains promoted indicators
            const hasPromotedIndicator = tweet.querySelector('[data-testid="promotedIndicator"]');
            let isPromotedText = false;

            // Search for "Ad", "Promoted", "赞助", "プロモーション" labels in spans/SVGs
            const textContainers = tweet.querySelectorAll('div[dir="ltr"] > span, span');
            for (let j = 0; j < textContainers.length; j++) {
                const text = textContainers[j].textContent.trim();
                if (text === "Promoted" || text === "Ad" || text === "赞助" || text === "プロモーション" || text === "Promovido") {
                    isPromotedText = true;
                    break;
                }
            }

            if (hasPromotedIndicator || isPromotedText) {
                const container = tweet.closest('div[data-testid="cellInnerDiv"]') || tweet;
                container.style.display = 'none';
            }
        }

        // Clean sidebar upsell banners
        const upsellSelectors = [
            'aside[role="complementary"] [data-testid="superFollowsUpsellBanner"]',
            'a[href*="/i/premium_sign_up"]',
            'a[href*="/i/verified-orgs-signup"]',
            'div[data-testid="GrokDrawer"]'
        ];
        upsellSelectors.forEach(selector => {
            const els = document.querySelectorAll(selector);
            els.forEach(el => {
                const box = el.closest('div[data-testid="cellInnerDiv"]') || el;
                box.style.display = 'none';
            });
        });
    }

    // 3. Set up DOM Mutation Observer for high efficiency
    let throttleTimeout = null;
    const observer = new MutationObserver(function() {
        if (!throttleTimeout) {
            throttleTimeout = setTimeout(function() {
                throttleTimeout = null;
                purgePromotedTweets();
                updateDockBadge();
            }, 100);
        }
    });

    observer.observe(document.documentElement, {
        childList: true,
        subtree: true
    });

    // Also observe title changes specifically
    const titleEl = document.querySelector('title');
    if (titleEl) {
        new MutationObserver(updateDockBadge).observe(titleEl, {
            subtree: true,
            characterData: true,
            childList: true
        });
    }

    // Initial pass when DOM loads
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
            purgePromotedTweets();
            updateDockBadge();
        });
    } else {
        purgePromotedTweets();
        updateDockBadge();
    }
})();
