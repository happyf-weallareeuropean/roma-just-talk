import SwiftUI
import AppKit

struct DashboardPromotionsSection: View {
    let licenseState: LicenseViewModel.LicenseState
    @State private var isAffiliatePromotionDismissed: Bool = UserDefaults.standard.affiliatePromotionDismissed

    private var shouldShowUpgradePromotion: Bool {
        switch licenseState {
        case .trial(let daysRemaining):
            return daysRemaining <= 3
        case .trialExpired:
            return true
        case .licensed:
            return false
        }
    }

    private var shouldShowAffiliatePromotion: Bool {
        if case .licensed = licenseState {
            return !isAffiliatePromotionDismissed
        }
        return false
    }
    
    private var shouldShowPromotions: Bool {
        shouldShowUpgradePromotion || shouldShowAffiliatePromotion
    }
    
    var body: some View {
        if shouldShowPromotions {
            HStack(alignment: .top, spacing: 18) {
                if shouldShowUpgradePromotion {
                    DashboardPromotionCard(
                        badge: "30% OFF",
                        title: "Unlock VoiceInk Pro For Less",
                        message: "Share VoiceInk on your socials, and instantly unlock a 30% discount on VoiceInk Pro.",
                        accentSymbol: "megaphone.fill",
                        glowColor: Color(red: 0.08, green: 0.48, blue: 0.85),
                        actionTitle: "Share & Unlock",
                        actionIcon: "arrow.up.right",
                        action: openSocialShare
                    )
                    .frame(maxWidth: .infinity)
                }
                
                if shouldShowAffiliatePromotion {
                    DashboardPromotionCard(
                        badge: "AFFILIATE 30%",
                        title: "Earn With The VoiceInk Affiliate Program",
                        message: "Share VoiceInk with friends or your audience and receive 30% on every referral that upgrades.",
                        accentSymbol: "link.badge.plus",
                        glowColor: Color(red: 0.08, green: 0.48, blue: 0.85),
                        actionTitle: "Explore Affiliate",
                        actionIcon: "arrow.up.right",
                        action: openAffiliateProgram,
                        onDismiss: dismissAffiliatePromotion
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            EmptyView()
        }
    }
    
    private func openSocialShare() {
        if let url = URL(string: "https://tryvoiceink.com/social-share") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openAffiliateProgram() {
        if let url = URL(string: "https://tryvoiceink.com/affiliate") {
            NSWorkspace.shared.open(url)
        }
    }

    private func dismissAffiliatePromotion() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isAffiliatePromotionDismissed = true
        }
        UserDefaults.standard.affiliatePromotionDismissed = true
    }
}

private struct DashboardPromotionCard: View {
    let badge: String
    let title: String
    let message: String
    let accentSymbol: String
    let glowColor: Color
    let actionTitle: String
    let actionIcon: String
    let action: () -> Void
    var onDismiss: (() -> Void)? = nil
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 13) {
                Text(badge.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: action) {
                    HStack(spacing: 6) {
                        Text(actionTitle)
                        Image(systemName: actionIcon)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(12)
                .help("Dismiss this promotion")
            }
        }
        .background(CardBackground(isSelected: false, cornerRadius: 22))
    }
}
