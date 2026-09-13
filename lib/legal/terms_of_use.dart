/// In-app Terms of Use and liability waiver shown during onboarding.
class TermsOfUse {
  TermsOfUse._();

  static const String pageTitle = "Sign the Terms of Use";

  static const String summary =
      "AvareX is unofficial software for situational awareness only. "
      "It is not an FAA-certified GPS or approved navigation, weather, "
      "traffic, terrain, or flight-planning system. You must assume it "
      "will fail or be wrong when life, health, or property are at risk. "
      "You, as pilot in command, are solely responsible for the flight. "
      "Apps4Av Inc. and everyone who writes, publishes, or distributes "
      "this software have no liability for your use of it.";

  static const List<TermsSection> liabilitySections = [
    TermsSection(
      "Not certified — supplemental use only",
      "AvareX is not FAA-certified, TSO'd, or otherwise approved as a "
      "navigation, communication, weather, traffic, terrain, obstacle, "
      "or flight-planning system. It is not a substitute for certified "
      "avionics, official FAA/government publications, an official "
      "weather briefing, current NOTAMs, or see-and-avoid. Do not use "
      "it as a sole or primary means of navigation or as a safety-critical "
      "system.",
    ),
    TermsSection(
      "Assume failure",
      "You must assume that this software, this device, the operating "
      "system, batteries, GPS, ADS-B, internet, downloaded charts and "
      "plates, weather, traffic, terrain, obstacles, performance numbers, "
      "weight-and-balance, AI outputs, community content, business "
      "listings, and every other display or calculation will fail, freeze, "
      "be delayed, be incomplete, or be wrong at any time — including in "
      "flight and when life, health, or property are at risk.",
    ),
    TermsSection(
      "Pilot in command",
      "You are solely responsible for the safe operation of the aircraft "
      "and for complying with all applicable regulations. You must "
      "independently verify any information before you rely on it and "
      "must always have approved backup sources. Nothing in AvareX "
      "reduces or transfers that responsibility.",
    ),
    TermsSection(
      "Third-party and user data",
      "Charts, plates, weather, traffic, airport data, AI responses, "
      "community posts, reviews, and similar content may come from "
      "government, third-party, or other users. Apps4Av does not create "
      "or control those sources and does not warrant that any such "
      "content is current, complete, or correct.",
    ),
    TermsSection(
      "No warranty",
      "THE SOFTWARE AND ALL DATA ARE PROVIDED \"AS IS\" AND \"AS "
      "AVAILABLE,\" WITH ALL FAULTS AND WITHOUT WARRANTY OF ANY KIND, "
      "EXPRESS OR IMPLIED, INCLUDING MERCHANTABILITY, FITNESS FOR A "
      "PARTICULAR PURPOSE, ACCURACY, COMPLETENESS, TIMELINESS, "
      "NON-INFRINGEMENT, OR UNINTERRUPTED OR ERROR-FREE OPERATION.",
    ),
    TermsSection(
      "Limitation of liability",
      "TO THE MAXIMUM EXTENT PERMITTED BY LAW, APPS4AV INC., ITS "
      "OFFICERS, DIRECTORS, SHAREHOLDERS, EMPLOYEES, CONTRACTORS, "
      "AGENTS, AFFILIATES, LICENSORS, CONTRIBUTORS, VOLUNTEERS, AND ANY "
      "PERSON WHO WRITES, PUBLISHES, OR DISTRIBUTES THIS SOFTWARE "
      "(COLLECTIVELY, \"APPS4AV\") SHALL HAVE NO LIABILITY FOR ANY "
      "CLAIM, LOSS, INJURY, DEATH, OR DAMAGE OF ANY KIND — INCLUDING "
      "PERSONAL INJURY, WRONGFUL DEATH, PROPERTY OR AIRCRAFT DAMAGE, "
      "DEVICE DAMAGE, NAVIGATION OR WEATHER ERROR, LOST DATA, LOST "
      "PROFITS, AND INCIDENTAL, CONSEQUENTIAL, SPECIAL, INDIRECT, OR "
      "PUNITIVE DAMAGES — ARISING FROM OR RELATED TO YOUR USE OF, "
      "INABILITY TO USE, OR RELIANCE ON THIS SOFTWARE OR ANY DATA IT "
      "DISPLAYS, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. "
      "IF ANY LIABILITY REMAINS, IT IS LIMITED TO THE AMOUNT YOU PAID "
      "APPS4AV FOR THE SOFTWARE IN THE TWELVE MONTHS BEFORE THE CLAIM, "
      "OR TEN US DOLLARS (US\$10), WHICHEVER IS GREATER.",
    ),
    TermsSection(
      "Assumption of risk and release",
      "You voluntarily assume all risk of using this software. You "
      "release and forever discharge Apps4Av from any and all claims "
      "arising from or related to your use of AvareX.",
    ),
    TermsSection(
      "Indemnity",
      "You agree to indemnify, defend, and hold harmless Apps4Av from "
      "any claim, demand, loss, or expense (including reasonable "
      "attorneys' fees) arising from your use of the software, your "
      "violation of these terms, or your violation of any law or "
      "third-party right.",
    ),
    TermsSection(
      "Acceptance and updates",
      "By tapping \"I Agree & Sign,\" you confirm that you have read, "
      "understood, and agree to these terms. If you do not agree, do "
      "not use this software. If a court finds any part unenforceable, "
      "the rest still applies. These terms are governed by the laws of "
      "the United States, without regard to conflict-of-law rules.",
    ),
  ];

  static const List<TermsSection> privacySections = [
    TermsSection(
      "What Information We Collect",
      "The Apps4Av online service collects identifiable account set-up "
      "information in the form of account username (e-mail address). "
      "This information must be provided in order to register and use "
      "our platform.",
    ),
    TermsSection(
      "Sharing Your Personal Information",
      "We do not sell or share your personal information to third "
      "parties for marketing purposes unless you have granted us "
      "permission to do so.",
    ),
    TermsSection(
      "Security",
      "We utilize generally accepted security measures (such as "
      "encryption / HTTPS) to protect against the misuse or unauthorized "
      "disclosure of any personal information you submit to us.",
    ),
    TermsSection(
      "Enforcement",
      "If you believe for any reason that we have not followed these "
      "privacy principles, please contact us at apps4av@gmail.com.",
    ),
  ];
}

class TermsSection {
  final String title;
  final String body;

  const TermsSection(this.title, this.body);
}
