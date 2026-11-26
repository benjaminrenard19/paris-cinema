import Foundation

extension Cinema {
    /// Paris cinemas shown on the map (same list as the Claude page).
    static let defaults: [Cinema] = [
        Cinema(name: "UGC Ciné Cité Les Halles", type: "Multiplex", address: "Forum des Halles, 7 place de la Rotonde, 75001", lat: 48.8622, lng: 2.3466),
        Cinema(name: "Le Grand Rex", type: "Landmark", address: "1 bd Poissonnière, 75002", lat: 48.8706, lng: 2.3477),
        Cinema(name: "Max Linder Panorama", type: "Landmark", address: "24 bd Poissonnière, 75009", lat: 48.8712, lng: 2.3445),
        Cinema(name: "Pathé Palace", type: "Multiplex", address: "2 bd des Capucines, 75009", lat: 48.8711, lng: 2.333),
        Cinema(name: "Pathé Wepler", type: "Multiplex", address: "140 bd de Clichy, 75018", lat: 48.8838, lng: 2.3275),
        Cinema(name: "Studio 28", type: "Art-house", address: "10 rue Tholozé, 75018", lat: 48.8857, lng: 2.3364),
        Cinema(name: "Le Louxor", type: "Art-house", address: "170 bd de Magenta, 75010", lat: 48.8836, lng: 2.3497),
        Cinema(name: "mk2 Quai de Seine & Quai de Loire", type: "Art-house", address: "14 quai de la Seine, 75019", lat: 48.8854, lng: 2.3705),
        Cinema(name: "Pathé La Villette", type: "Multiplex", address: "30 av. Corentin-Cariou, 75019", lat: 48.8935, lng: 2.3897),
        Cinema(name: "mk2 Beaubourg", type: "Art-house", address: "50 rue Rambuteau, 75003", lat: 48.8615, lng: 2.3529),
        Cinema(name: "Luminor Hôtel de Ville", type: "Art-house", address: "20 rue du Temple, 75004", lat: 48.858, lng: 2.354),
        Cinema(name: "Le Champo", type: "Repertory", address: "51 rue des Écoles, 75005", lat: 48.8502, lng: 2.3437),
        Cinema(name: "Reflet Médicis & Filmothèque", type: "Repertory", address: "3 and 9 rue Champollion, 75005", lat: 48.8497, lng: 2.342),
        Cinema(name: "Le Grand Action", type: "Repertory", address: "5 rue des Écoles, 75005", lat: 48.8488, lng: 2.353),
        Cinema(name: "Christine Cinéma Club", type: "Repertory", address: "4 rue Christine, 75006", lat: 48.8547, lng: 2.3408),
        Cinema(name: "Saint-André des Arts", type: "Art-house", address: "30 rue Saint-André-des-Arts, 75006", lat: 48.853, lng: 2.3427),
        Cinema(name: "mk2 Odéon", type: "Art-house", address: "113 bd Saint-Germain, 75006", lat: 48.8519, lng: 2.3386),
        Cinema(name: "Les 7 Parnassiens", type: "Art-house", address: "98 bd du Montparnasse, 75014", lat: 48.8425, lng: 2.3292),
        Cinema(name: "Pathé Parnasse", type: "Multiplex", address: "3 rue d'Odessa, 75014", lat: 48.8429, lng: 2.324),
        Cinema(name: "Escurial", type: "Landmark", address: "11 bd de Port-Royal, 75013", lat: 48.8366, lng: 2.3517),
        Cinema(name: "mk2 Bibliothèque", type: "Multiplex", address: "128-162 av. de France, 75013", lat: 48.8317, lng: 2.3773),
        Cinema(name: "Cinémathèque française", type: "Repertory", address: "51 rue de Bercy, 75012", lat: 48.8373, lng: 2.3826),
        Cinema(name: "UGC Ciné Cité Bercy", type: "Multiplex", address: "2 cour Saint-Émilion, 75012", lat: 48.8333, lng: 2.3866),
        Cinema(name: "mk2 Nation", type: "Art-house", address: "133 bd Diderot, 75012", lat: 48.8476, lng: 2.3926),
        Cinema(name: "mk2 Gambetta", type: "Multiplex", address: "6 rue Belgrand, 75020", lat: 48.865, lng: 2.3985),
        Cinema(name: "Pathé Beaugrenelle", type: "Multiplex", address: "7 rue Linois, 75015", lat: 48.8486, lng: 2.2827),
        Cinema(name: "UGC Normandie", type: "Landmark", address: "116 bis av. des Champs-Élysées, 75008", lat: 48.8719, lng: 2.3005),
        Cinema(name: "Elysées Lincoln", type: "Art-house", address: "14 rue Lincoln, 75008", lat: 48.8712, lng: 2.304),
        Cinema(name: "Le Balzac", type: "Art-house", address: "1 rue Balzac, 75008", lat: 48.8737, lng: 2.2992),
    ]

    static let types = ["Multiplex", "Art-house", "Repertory", "Landmark"]

    static func typeBlurb(_ t: String) -> String {
        switch t {
        case "Multiplex": return "Big screens, new releases, dubbed and original versions"
        case "Art-house": return "Original versions with subtitles, auteur and foreign films"
        case "Repertory": return "Classics, re-releases and retrospectives"
        default: return "Historic big single screens"
        }
    }
}
