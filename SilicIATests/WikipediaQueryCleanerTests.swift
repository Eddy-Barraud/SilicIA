//
//  WikipediaQueryCleanerTests.swift
//  SilicIATests
//
//  Unit tests for WikipediaQueryCleaner across English, French, and Spanish.
//

import XCTest
@testable import SilicIA

final class WikipediaQueryCleanerTests: XCTestCase {

    func testEnglishCleaning() {
        let cases: [(String, String)] = [
            ("Who was the first president of the United States?", "first president United States"),
            ("What is photosynthesis?", "photosynthesis"),
            ("Where is the Eiffel Tower located?", "Eiffel Tower located"),
            ("When was Apollo 11 launched?", "Apollo 11 launched"),
            ("Why does the moon have phases?", "moon phases"),
            ("How does an airplane fly?", "airplane fly"),
            ("How to bake sourdough bread?", "bake sourdough bread"),
            ("Can you tell me about quantum computing?", "quantum computing"),
            ("Tell me about Albert Einstein", "Albert Einstein"),
            ("Explain the theory of general relativity.", "theory general relativity")
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(WikipediaQueryCleaner.clean(raw), expected, "Failed for '\(raw)'")
        }
    }

    func testFrenchAndSpanishCleaning() {
        let cases: [(String, String)] = [
            // French questions & fluff
            ("Qu'est-ce que la relativité générale ?", "relativité générale"),
            ("C'est quoi l'intelligence artificielle ?", "intelligence artificielle"),
            ("Qui est Marie Curie ?", "Marie Curie"),
            ("Où se trouve la Tour Eiffel ?", "Tour Eiffel"),
            ("Comment fonctionne l'ADN ?", "ADN"),
            ("Peux-tu m'expliquer la photosynthèse ?", "photosynthèse"),
            ("l'astronomie moderne", "astronomie moderne"),
            ("théorie d'Einstein", "théorie Einstein"),
            // Spanish questions & inverted punctuation
            ("¿Quién fue Simón Bolívar?", "Simón Bolívar"),
            ("¿Qué es la fotosíntesis?", "fotosíntesis"),
            ("¿Dónde está la Alhambra?", "Alhambra"),
            ("¿Cómo funciona un motor eléctrico?", "motor eléctrico"),
            ("¿Cuándo ocurrió la Revolución Francesa?", "Revolución Francesa")
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(WikipediaQueryCleaner.clean(raw), expected, "Failed for '\(raw)'")
        }
    }

    func testEdgeCasesAndFallbacks() {
        // Fallback when all words are stop words
        XCTAssertEqual(WikipediaQueryCleaner.clean("The Who"), "The Who")
        XCTAssertEqual(WikipediaQueryCleaner.clean("Why?"), "Why")

        // Empty and punctuation-only inputs
        XCTAssertEqual(WikipediaQueryCleaner.clean(""), "")
        XCTAssertEqual(WikipediaQueryCleaner.clean("   "), "")
        XCTAssertEqual(WikipediaQueryCleaner.clean("???"), "")

        // Quotes and punctuation stripping
        XCTAssertEqual(WikipediaQueryCleaner.clean("\"James Webb Space Telescope\"?"), "James Webb Space Telescope")
        XCTAssertEqual(WikipediaQueryCleaner.clean("« Tour Eiffel »!"), "Tour Eiffel")

        // Idempotence
        let q = "Who was the first president of the United States?"
        XCTAssertEqual(WikipediaQueryCleaner.clean(q), WikipediaQueryCleaner.clean(WikipediaQueryCleaner.clean(q)))
    }
}
