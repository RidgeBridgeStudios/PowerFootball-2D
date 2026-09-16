#!/usr/bin/env python3
"""
tools/generate_phony_db.py

Generates a complete, realistic fictional world football database covering the top 20 leagues
in the world (~392 clubs, ~7,056 players, 1,960 backroom staff, 392 managers, 24 referees).

Outputs:
- data/world_manifest.json: Sharded manifest referencing 20 division shard files
- data/shards/<nation_key>_t1.json: 20 division shard files with full squad and staff data
- data/world_managers.json: All 392 club managers plus free agents
- data/world_referees.json: International referee pool across all 20 nations
- data/world_staff.json: Complete staff directory across all clubs
"""

import json
import os
import random
import sys

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "data")
SHARDS_DIR = os.path.join(DATA_DIR, "shards")

random.seed(42)

# --- Nation & League Pyramid Definitions (Top 20 Nations) ---
NATIONS_DATA = [
    {
        "nation": "England", "key": "england", "confed": "UEFA", "lang": "English",
        "league_name": "Premier League", "team_count": 20, "relegation_slots": 3,
        "base_rep": 0.82, "rep_spread": 0.18,
        "cities": ["London", "Manchester", "Liverpool", "Birmingham", "Newcastle", "Leeds", "Sheffield", "Bristol", "Nottingham", "Leicester", "Southampton", "Brighton", "Wolverhampton", "Coventry", "Norwich", "Sunderland", "Middlesbrough", "Blackburn", "Stoke", "Derby"]
    },
    {
        "nation": "Spain", "key": "spain", "confed": "UEFA", "lang": "Spanish",
        "league_name": "La Liga", "team_count": 20, "relegation_slots": 3,
        "base_rep": 0.80, "rep_spread": 0.20,
        "cities": ["Madrid", "Barcelona", "Valencia", "Sevilla", "Bilbao", "San Sebastian", "Villarreal", "Vigo", "Getafe", "Mallorca", "Pamplona", "Girona", "Granada", "Cadiz", "Almeria", "Valladolid", "Zaragoza", "Oviedo", "Santander", "Elche"]
    },
    {
        "nation": "Germany", "key": "germany", "confed": "UEFA", "lang": "German",
        "league_name": "Bundesliga", "team_count": 18, "relegation_slots": 2,
        "base_rep": 0.79, "rep_spread": 0.19,
        "cities": ["Munich", "Dortmund", "Leipzig", "Leverkusen", "Frankfurt", "Stuttgart", "Wolfsburg", "Monchengladbach", "Berlin", "Bremen", "Hoffenheim", "Freiburg", "Augsburg", "Mainz", "Bochum", "Cologne", "Hamburg", "Schalke"]
    },
    {
        "nation": "Italy", "key": "italy", "confed": "UEFA", "lang": "Italian",
        "league_name": "Serie A", "team_count": 20, "relegation_slots": 3,
        "base_rep": 0.79, "rep_spread": 0.19,
        "cities": ["Milan", "Rome", "Turin", "Naples", "Bergamo", "Florence", "Bologna", "Genoa", "Verona", "Udine", "Monza", "Cagliari", "Lecce", "Empoli", "Salerno", "Palermo", "Bari", "Venice", "Parma", "Brescia"]
    },
    {
        "nation": "France", "key": "france", "confed": "UEFA", "lang": "French",
        "league_name": "Ligue 1", "team_count": 18, "relegation_slots": 2,
        "base_rep": 0.76, "rep_spread": 0.20,
        "cities": ["Paris", "Marseille", "Lyon", "Monaco", "Lille", "Rennes", "Nice", "Lens", "Strasbourg", "Nantes", "Reims", "Toulouse", "Montpellier", "Brest", "Lorient", "Bordeaux", "Saint-Etienne", "Metz"]
    },
    {
        "nation": "Netherlands", "key": "netherlands", "confed": "UEFA", "lang": "Dutch",
        "league_name": "Eredivisie", "team_count": 18, "relegation_slots": 2,
        "base_rep": 0.72, "rep_spread": 0.22,
        "cities": ["Amsterdam", "Rotterdam", "Eindhoven", "Alkmaar", "Utrecht", "Enschede", "Arnhem", "Heerenveen", "Nijmegen", "Groningen", "Zwolle", "Tilburg", "Deventer", "Breda", "Sittard", "Almere", "Volendam", "The Hague"]
    },
    {
        "nation": "Portugal", "key": "portugal", "confed": "UEFA", "lang": "Portuguese",
        "league_name": "Primeira Liga", "team_count": 18, "relegation_slots": 2,
        "base_rep": 0.72, "rep_spread": 0.24,
        "cities": ["Lisbon", "Porto", "Braga", "Guimaraes", "Faro", "Funchal", "Coimbra", "Setubal", "Aveiro", "Barcelos", "Arouca", "Vila do Conde", "Estoril", "Portimao", "Vizela", "Chaves", "Moreira de Conegos", "Amadora"]
    },
    {
        "nation": "Brazil", "key": "brazil", "confed": "CONMEBOL", "lang": "Portuguese",
        "league_name": "Série A", "team_count": 20, "relegation_slots": 4,
        "base_rep": 0.75, "rep_spread": 0.20,
        "cities": ["Sao Paulo", "Rio de Janeiro", "Belo Horizonte", "Porto Alegre", "Salvador", "Curitiba", "Fortaleza", "Recife", "Brasilia", "Goiania", "Santos", "Campinas", "Florianopolis", "Belem", "Manaus", "Cuiaba", "Natal", "Vitoria", "Chapeco", "Joinville"]
    },
    {
        "nation": "Argentina", "key": "argentina", "confed": "CONMEBOL", "lang": "Spanish",
        "league_name": "Liga Profesional", "team_count": 28, "relegation_slots": 2,
        "base_rep": 0.74, "rep_spread": 0.22,
        "cities": ["Buenos Aires", "Rosario", "Cordoba", "La Plata", "Santa Fe", "Mendoza", "Tucuman", "Avellaneda", "Mar del Plata", "San Juan", "Lanus", "Banfield", "Quilmes", "Victoria", "Parana", "Junin", "Santiago del Estero", "Resistencia", "Bahia Blanca", "Posadas", "Salta", "Corrientes", "Neuquen", "Rafaela", "San Nicolas", "Pergamino", "Tandil", "Campana"]
    },
    {
        "nation": "Scotland", "key": "scotland", "confed": "UEFA", "lang": "English",
        "league_name": "Scottish Premiership", "team_count": 12, "relegation_slots": 1,
        "base_rep": 0.65, "rep_spread": 0.25,
        "cities": ["Glasgow", "Edinburgh", "Aberdeen", "Dundee", "Perth", "Paisley", "Motherwell", "Kilmarnock", "Livingston", "Inverness", "Kirkcaldy", "Falkirk"]
    },
    {
        "nation": "Norway", "key": "norway", "confed": "UEFA", "lang": "Norwegian",
        "league_name": "Eliteserien", "team_count": 16, "relegation_slots": 2,
        "base_rep": 0.62, "rep_spread": 0.18,
        "cities": ["Oslo", "Bergen", "Trondheim", "Stavanger", "Bodo", "Molde", "Drammen", "Kristiansand", "Tromso", "Sarpsborg", "Sandefjord", "Haugesund", "Lillestrom", "Aalesund", "Skien", "Fredrikstad"]
    },
    {
        "nation": "Sweden", "key": "sweden", "confed": "UEFA", "lang": "Swedish",
        "league_name": "Allsvenskan", "team_count": 16, "relegation_slots": 2,
        "base_rep": 0.62, "rep_spread": 0.18,
        "cities": ["Stockholm", "Gothenburg", "Malmo", "Uppsala", "Vasteras", "Orebro", "Linkoping", "Helsingborg", "Jonkoping", "Norrkoping", "Lund", "Umea", "Gavle", "Boras", "Halmstad", "Vaxjo"]
    },
    {
        "nation": "Denmark", "key": "denmark", "confed": "UEFA", "lang": "Danish",
        "league_name": "Superliga", "team_count": 12, "relegation_slots": 2,
        "base_rep": 0.64, "rep_spread": 0.18,
        "cities": ["Copenhagen", "Aarhus", "Odense", "Aalborg", "Esbjerg", "Randers", "Kolding", "Horsens", "Vejle", "Herning", "Silkeborg", "Farum"]
    },
    {
        "nation": "Poland", "key": "poland", "confed": "UEFA", "lang": "Polish",
        "league_name": "Ekstraklasa", "team_count": 18, "relegation_slots": 3,
        "base_rep": 0.61, "rep_spread": 0.17,
        "cities": ["Warsaw", "Krakow", "Lodz", "Wroclaw", "Poznan", "Gdansk", "Szczecin", "Bydgoszcz", "Lublin", "Bialystok", "Katowice", "Gdynia", "Czestochowa", "Radom", "Sosnowiec", "Torun", "Kielce", "Gliwice"]
    },
    {
        "nation": "Belgium", "key": "belgium", "confed": "UEFA", "lang": "Dutch",
        "league_name": "Pro League", "team_count": 16, "relegation_slots": 2,
        "base_rep": 0.70, "rep_spread": 0.20,
        "cities": ["Brussels", "Antwerp", "Ghent", "Bruges", "Liege", "Leuven", "Genk", "Charleroi", "Anderlecht", "Mechelen", "Kortrijk", "Ostend", "Sint-Truiden", "Eupen", "Westerlo", "Cercle Bruges"]
    },
    {
        "nation": "Turkey", "key": "turkey", "confed": "UEFA", "lang": "Turkish",
        "league_name": "Süper Lig", "team_count": 19, "relegation_slots": 4,
        "base_rep": 0.68, "rep_spread": 0.22,
        "cities": ["Istanbul", "Ankara", "Izmir", "Bursa", "Antalya", "Adana", "Konya", "Gaziantep", "Trabzon", "Samsun", "Diyarbakir", "Kayseri", "Eskisehir", "Mersin", "Denizli", "Malatya", "Sivas", "Rize", "Alanya"]
    },
    {
        "nation": "Russia", "key": "russia", "confed": "UEFA", "lang": "Russian",
        "league_name": "Russian Premier League", "team_count": 16, "relegation_slots": 2,
        "base_rep": 0.67, "rep_spread": 0.20,
        "cities": ["Moscow", "Saint Petersburg", "Kazan", "Rostov", "Krasnodar", "Samara", "Yekaterinburg", "Nizhny Novgorod", "Sochi", "Voronezh", "Grozny", "Orenburg", "Tula", "Ufa", "Perm", "Yaroslavl"]
    },
    {
        "nation": "Mexico", "key": "mexico", "confed": "CONCACAF", "lang": "Spanish",
        "league_name": "Liga MX", "team_count": 18, "relegation_slots": 0,
        "base_rep": 0.70, "rep_spread": 0.18,
        "cities": ["Mexico City", "Guadalajara", "Monterrey", "Puebla", "Toluca", "Tijuana", "Leon", "Juarez", "Torreon", "San Luis Potosi", "Queretaro", "Aguascalientes", "Mazatlan", "Pachuca", "Cuernavaca", "Morelia", "Veracruz", "Hermosillo"]
    },
    {
        "nation": "United States", "key": "usa", "confed": "CONCACAF", "lang": "English",
        "league_name": "Major League Soccer", "team_count": 29, "relegation_slots": 0,
        "base_rep": 0.69, "rep_spread": 0.16,
        "cities": ["New York", "Los Angeles", "Chicago", "Houston", "Atlanta", "Miami", "Seattle", "Portland", "Philadelphia", "Toronto", "Montreal", "Vancouver", "Boston", "Dallas", "Denver", "Salt Lake City", "Kansas City", "Columbus", "Cincinnati", "Nashville", "Austin", "Charlotte", "Minneapolis", "St. Louis", "Orlando", "San Jose", "Washington", "San Diego", "Detroit"]
    },
    {
        "nation": "Japan", "key": "japan", "confed": "AFC", "lang": "Japanese",
        "league_name": "J1 League", "team_count": 20, "relegation_slots": 3,
        "base_rep": 0.65, "rep_spread": 0.17,
        "cities": ["Tokyo", "Yokohama", "Osaka", "Nagoya", "Sapporo", "Fukuoka", "Kobe", "Kyoto", "Kawasaki", "Saitama", "Hiroshima", "Sendai", "Chiba", "Niigata", "Shizuoka", "Hamamatsu", "Kashima", "Tosun", "Kashiwa", "Shonan"]
    }
]

# --- Cultural Name Pools per Nationality ---
NAME_POOLS = {
    "English": {
        "first": ["Oliver", "George", "Harry", "Jack", "Jacob", "Noah", "Charlie", "Thomas", "Oscar", "William", "James", "Henry", "Alfie", "Leo", "Archie", "Arthur", "Logan", "Freddie", "Edward", "Liam"],
        "last": ["Smith", "Jones", "Taylor", "Brown", "Williams", "Wilson", "Johnson", "Davies", "Robinson", "Wright", "Thompson", "Evans", "Walker", "White", "Roberts", "Green", "Hall", "Wood", "Clarke", "Cooper"]
    },
    "Spanish": {
        "first": ["Alejandro", "Daniel", "Pablo", "Alvaro", "Adrian", "David", "Diego", "Javier", "Mario", "Sergio", "Marcos", "Manuel", "Carlos", "Ivan", "Ruben", "Gonzalo", "Raul", "Jorge", "Mateo", "Hugo"],
        "last": ["Garcia", "Rodriguez", "Gonzalez", "Fernandez", "Lopez", "Martinez", "Sanchez", "Perez", "Gomez", "Martin", "Jimenez", "Ruiz", "Hernandez", "Diaz", "Moreno", "Alvarez", "Romero", "Alonso", "Torres", "Navarro"]
    },
    "German": {
        "first": ["Maximilian", "Alexander", "Paul", "Elias", "Louis", "Leon", "Lukas", "Felix", "Noah", "Jonas", "Finn", "Ben", "Niklas", "Tim", "Julian", "Moritz", "Philipp", "Jan", "David", "Florian"],
        "last": ["Muller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer", "Wagner", "Becker", "Schulz", "Hoffmann", "Schäfer", "Koch", "Bauer", "Richter", "Klein", "Wolf", "Schröder", "Neumann", "Schwarz", "Zimmermann"]
    },
    "Italian": {
        "first": ["Francesco", "Alessandro", "Leonardo", "Lorenzo", "Mattia", "Andrea", "Gabriele", "Matteo", "Tommaso", "Riccardo", "Edoardo", "Federico", "Giuseppe", "Antonio", "Marco", "Pietro", "Davide", "Christian", "Luca", "Simone"],
        "last": ["Rossi", "Russo", "Ferrari", "Esposito", "Bianchi", "Romano", "Colombo", "Ricci", "Marino", "Greco", "Bruno", "Gallo", "Conti", "De Luca", "Mancini", "Costa", "Giordano", "Rizzo", "Lombardi", "Moretti"]
    },
    "French": {
        "first": ["Lucas", "Maxime", "Antoine", "Theo", "Alexandre", "Julien", "Clement", "Nicolas", "Romain", "Mathieu", "Hugo", "Adrien", "Florian", "Bastien", "Leo", "Gabin", "Valentin", "Arthur", "Gabriel", "Raphael"],
        "last": ["Dubois", "Moreau", "Laurent", "Simon", "Michel", "Lefebvre", "Leroy", "Roux", "David", "Bertrand", "Morel", "Fournier", "Girard", "Bonnet", "Dupont", "Lambert", "Fontaine", "Rousseau", "Vincent", "Muller"]
    },
    "Dutch": {
        "first": ["Daan", "Sem", "Lucas", "Milan", "Levi", "Finn", "Jesse", "Liam", "Thomas", "Bram", "Luuk", "Sam", "Thijs", "Tim", "Jayden", "Lars", "Ruben", "Mees", "Sven", "Stijn"],
        "last": ["de Jong", "Jansen", "de Vries", "van den Berg", "van Dijk", "Bakker", "Janssen", "Visser", "Smit", "Meijer", "de Boer", "Mulder", "de Groot", "Bos", "Vos", "Peters", "Hendriks", "van Leeuwen", "Dekker", "Brouwer"]
    },
    "Portuguese": {
        "first": ["Joao", "Rodrigo", "Martim", "Afonso", "Francisco", "Tomas", "Duarte", "Miguel", "Tiago", "Diogo", "Pedro", "Goncalo", "Guilherme", "Lucas", "Santiago", "Bernardo", "Rafael", "Andre", "Gabriel", "Mateus"],
        "last": ["Silva", "Santos", "Ferreira", "Pereira", "Oliveira", "Costa", "Rodrigues", "Martins", "Jesus", "Sousa", "Fernandes", "Goncalves", "Gomes", "Lopes", "Marques", "Alves", "Almeida", "Ribeiro", "Pinto", "Carvalho"]
    },
    "Norwegian": {
        "first": ["Jakob", "Lucas", "Emil", "Oskar", "Oliver", "Filip", "Noah", "Elias", "Isak", "Aksel", "Magnus", "Henrik", "Tobias", "Sander", "Hakon", "Johannes", "Sigurd", "Sondre", "Kristian", "Even"],
        "last": ["Hansen", "Johansen", "Olsen", "Larsen", "Andersen", "Pedersen", "Nilsen", "Kristiansen", "Jensen", "Karlsen", "Johnsen", "Pettersen", "Eriksen", "Berg", "Haugen", "Hagen", "Johannessen", "Andreassen", "Jacobsen", "Dahl"]
    },
    "Swedish": {
        "first": ["William", "Liam", "Elias", "Noah", "Hugo", "Lucas", "Oliver", "Oscar", "Adam", "Alexander", "Leo", "Viktor", "Filip", "Emil", "Isak", "Axel", "Albin", "Arvid", "Ludvig", "Theo"],
        "last": ["Andersson", "Johansson", "Karlsson", "Nilsson", "Eriksson", "Larsson", "Olsson", "Persson", "Svensson", "Gustafsson", "Pettersson", "Jonsson", "Jansson", "Hansson", "Bengtsson", "Carlsson", "Lindberg", "Magnusson", "Lindqvist", "Lindgren"]
    },
    "Danish": {
        "first": ["William", "Noah", "Lucas", "Victor", "Emil", "Oliver", "Magnus", "Frederik", "Alexander", "Christian", "Elias", "Mads", "Mikkel", "Valdemar", "Oscar", "Malthe", "Mathias", "Sebastian", "Villads", "Johan"],
        "last": ["Nielsen", "Jensen", "Hansen", "Pedersen", "Andersen", "Christensen", "Larsen", "Sorensen", "Rasmussen", "Jorgensen", "Petersen", "Madsen", "Kristensen", "Olsen", "Thomsen", "Christiansen", "Poulsen", "Johansen", "Moller", "Mortensen"]
    },
    "Polish": {
        "first": ["Antoni", "Jakub", "Jan", "Szymon", "Aleksander", "Franciszek", "Filip", "Mikolaj", "Wojciech", "Kacper", "Adam", "Michal", "Marcel", "Stanislaw", "Wiktor", "Piotr", "Igor", "Mateusz", "Bartosz", "Maksymilian"],
        "last": ["Nowak", "Kowalski", "Wisniewski", "Dabrowski", "Lewandowski", "Wojcik", "Kaminski", "Kowalczyk", "Zielinski", "Szymanski", "Wozniak", "Kozlowski", "Jankowski", "Mazur", "Wojciechowski", "Kwiatkowski", "Krawczyk", "Kaczmarek", "Piotrowski", "Grabowski"]
    },
    "Turkish": {
        "first": ["Yusuf", "Mirac", "Eymen", "Omer", "Kerem", "Mustafa", "Hamza", "Ali", "Ahmet", "Mehmet", "Emir", "Ibrahim", "Can", "Burak", "Arda", "Hakan", "Emre", "Baris", "Kaan", "Oguz"],
        "last": ["Yilmaz", "Kaya", "Demir", "Celik", "Sahin", "Yildiz", "Yildirim", "Ozturk", "Aydin", "Ozdemir", "Arslan", "Dogan", "Kilic", "Aslan", "Cetin", "Kara", "Koc", "Kurt", "Ozkan", "Simsek"]
    },
    "Russian": {
        "first": ["Alexander", "Mikhail", "Maxim", "Artem", "Ivan", "Dmitry", "Daniil", "Mark", "Matvey", "Ilya", "Kirill", "Roman", "Timofey", "Nikita", "Andrey", "Fedor", "Egor", "Yaroslav", "Konstantin", "Vladimir"],
        "last": ["Ivanov", "Smirnov", "Kuznetsov", "Popov", "Vasiliev", "Petrov", "Sokolov", "Mikhailov", "Novikov", "Fedorov", "Morozov", "Volkov", "Alekseev", "Lebedev", "Semenov", "Egorov", "Pavlov", "Kozlov", "Stepanov", "Nikolaev"]
    },
    "Japanese": {
        "first": ["Ren", "Hiroto", "Haruto", "Sota", "Yuto", "Riku", "Minato", "Yuma", "Kaito", "Asahi", "Takumi", "Daiki", "Kenji", "Shota", "Ryota", "Kazuki", "Hayato", "Kenta", "Naoki", "Tsubasa"],
        "last": ["Sato", "Suzuki", "Takahashi", "Tanaka", "Watanabe", "Ito", "Yamamoto", "Nakamura", "Kobayashi", "Kato", "Yoshida", "Yamada", "Sasaki", "Yamaguchi", "Saito", "Matsumoto", "Inoue", "Kimura", "Hayashi", "Shimizu"]
    }
}

# Add alias fallbacks
NAME_POOLS["Scottish"] = NAME_POOLS["English"]
NAME_POOLS["Argentine"] = NAME_POOLS["Spanish"]
NAME_POOLS["Brazilian"] = NAME_POOLS["Portuguese"]
NAME_POOLS["Mexican"] = NAME_POOLS["Spanish"]
NAME_POOLS["Belgian"] = NAME_POOLS["French"]

CLUBS_SUFFIXES = {
    "England": ["FC", "United", "City", "Rovers", "Town", "Athletic", "Albion", "Wanderers"],
    "Spain": ["Real", "CF", "Atletico", "Deportivo", "Sporting", "Union"],
    "Germany": ["FC", "SV", "SC", "VfB", "VfL", "Borussia", "Eintracht"],
    "Italy": ["Calcio", "AC", "AS", "FC", "Inter", "Sportiva", "Virtus"],
    "France": ["Olympique", "FC", "AS", "Stade", "Sporting", "Racing"],
    "Netherlands": ["FC", "SC", "Sparta", "Willem", "Fortuna", "Excelsior"],
    "Portugal": ["FC", "Sporting", "SC", "Boavista", "Uniao", "Vitoria"],
    "Brazil": ["FC", "EC", "Atletico", "Sport", "Gremio", "Cruzeiro", "Fluminense"],
    "Argentina": ["Atletico", "Racing", "Independiente", "San", "Club", "Deportivo"],
    "Scotland": ["FC", "United", "Thistle", "Athletic", "Rovers", "Hearts"],
    "Norway": ["FK", "IL", "SK", "Fotball", "Glimt", "Viking"],
    "Sweden": ["IF", "FF", "AIK", "BK", "BoIS", "Dalkurd"],
    "Denmark": ["BK", "FC", "IF", "Boldklub", "Fremad"],
    "Poland": ["FC", "Gornik", "Wisla", "Legia", "Lech", "Zaglebie", "Pogon"],
    "Belgium": ["KAA", "KRC", "KV", "Standard", "Union", "Royal"],
    "Turkey": ["SK", "FK", "Spor", "Demirspor", "Birligi"],
    "Russia": ["FC", "Spartak", "Dynamo", "Lokomotiv", "Zenit", "Torpedo", "CSKA"],
    "Mexico": ["FC", "CF", "Club", "Tigres", "Atlas", "Toluca", "Puebla"],
    "United States": ["FC", "SC", "City SC", "United", "Republic", "Dynamo"],
    "Japan": ["FC", "Gamba", "Frontale", "Antlers", "Marinos", "Grampus", "Sanfrecce"]
}

PALETTES = [
    ([0.85, 0.12, 0.15], [1.0, 1.0, 1.0]),     # Red & White
    ([0.10, 0.25, 0.65], [1.0, 1.0, 1.0]),     # Royal Blue & White
    ([0.08, 0.15, 0.35], [0.90, 0.75, 0.15]),  # Navy & Gold
    ([0.15, 0.50, 0.25], [1.0, 1.0, 1.0]),     # Emerald & White
    ([0.12, 0.12, 0.14], [0.85, 0.12, 0.15]),  # Black & Red
    ([0.90, 0.85, 0.10], [0.10, 0.10, 0.10]),  # Yellow & Black
    ([0.45, 0.10, 0.25], [0.40, 0.65, 0.85]),  # Claret & Sky Blue
    ([0.95, 0.50, 0.10], [0.10, 0.10, 0.10]),  # Orange & Black
    ([0.10, 0.10, 0.10], [1.0, 1.0, 1.0]),     # Black & White
    ([0.35, 0.15, 0.50], [1.0, 1.0, 1.0]),     # Purple & White
]

FORMATIONS = ["4-3-3", "4-2-3-1", "4-4-2", "3-5-2", "5-3-2", "4-1-4-1"]

SQUAD_ROLES = ["GK", "LB", "CB", "CB", "RB", "LM", "CM", "DM", "RM", "ST", "ST", "GK", "CB", "RB", "CM", "AM", "ST", "CB"]

def clamp(val, min_v, max_v):
    return max(min_v, min(max_v, val))

def get_stature(reputation):
    if reputation >= 0.80:
        return "Continental Giant"
    elif reputation >= 0.65:
        return "Top Flight Heavyweight"
    elif reputation >= 0.50:
        return "Mid-Table Regular"
    elif reputation >= 0.40:
        return "Relegation Battler"
    else:
        return "Lower League Underdog"

def generate_player(p_idx, role, nat, lang, team_name, club_rep):
    pool = NAME_POOLS.get(nat, NAME_POOLS["English"])
    first = pool["first"][p_idx % len(pool["first"])]
    last = pool["last"][(p_idx * 3 + random.randint(0, 10)) % len(pool["last"])]
    pname = f"{first} {last}"
    shirt_num = p_idx + 1 if p_idx < 11 else p_idx + 10

    is_starter = p_idx < 11
    quality = clamp(club_rep + random.uniform(-0.12, 0.08), 0.35, 0.95)
    
    # Strictly bounded physical attributes
    mass = 82.0 if role == "GK" else (80.0 if "CB" in role else random.uniform(68.0, 80.0))
    top_speed = 185.0 if role == "GK" else clamp(195.0 + quality * 45.0 + random.uniform(-10.0, 10.0), 175.0, 255.0)
    accel = 0.28 if role == "GK" else clamp(0.28 - quality * 0.10 + random.uniform(-0.03, 0.03), 0.14, 0.35)
    frict = 0.12
    turn_pen = clamp(0.42 - quality * 0.15 + random.uniform(-0.05, 0.05), 0.20, 0.50)
    sprint_mult = 1.45
    stamina = 90.0 if role == "GK" else clamp(85.0 + quality * 30.0 + random.uniform(-5.0, 5.0), 78.0, 120.0)

    # Strictly bounded mental attributes (0.0 to 1.0)
    vision = clamp(quality + random.uniform(-0.15, 0.15), 0.10, 0.95) if role != "GK" else random.uniform(0.40, 0.60)
    composure = clamp(quality + random.uniform(-0.12, 0.12), 0.15, 0.95)
    aggression = round(random.uniform(0.35, 0.85), 2)
    close_ctrl = clamp(quality + random.uniform(-0.10, 0.15), 0.20, 0.95) if role != "GK" else random.uniform(0.35, 0.55)
    reflexes = clamp(quality + random.uniform(0.05, 0.25), 0.55, 0.98) if role == "GK" else random.uniform(0.30, 0.60)
    form = round(clamp(random.uniform(5.8, 7.8), 1.0, 10.0), 1)

    det = round(clamp(random.uniform(0.45, 0.85), 0.0, 1.0), 2)
    wr = round(clamp(random.uniform(0.45, 0.90), 0.0, 1.0), 2)
    lead = round(clamp(random.uniform(0.30, 0.85) if (p_idx == 2 or is_starter) else random.uniform(0.20, 0.60), 0.0, 1.0), 2)
    temp = round(clamp(random.uniform(0.40, 0.80), 0.0, 1.0), 2)
    prof = round(clamp(random.uniform(0.45, 0.90), 0.0, 1.0), 2)
    amb = round(clamp(random.uniform(0.40, 0.85), 0.0, 1.0), 2)
    loy = round(clamp(random.uniform(0.45, 0.80), 0.0, 1.0), 2)
    adapt = round(clamp(random.uniform(0.45, 0.80), 0.0, 1.0), 2)

    rep = round(clamp(club_rep + random.uniform(-0.10, 0.10), 0.10, 0.98), 2)
    wage = max(int(rep * 120000 * random.uniform(0.8, 1.2) / 1000) * 1000, 1200)
    mval = max(int(rep * 45000000 * random.uniform(0.7, 1.3) / 50000) * 50000, 50000)

    dob_year = random.randint(1993, 2006)
    dob_month = random.randint(1, 12)
    dob_day = random.randint(1, 28)
    dob = f"{dob_year}-{dob_month:02d}-{dob_day:02d}"

    spoken = [{"language": lang, "proficiency": 1.0, "level": "Native"}]
    if lang != "English":
        spoken.append({"language": "English", "proficiency": round(random.uniform(0.60, 0.90), 2), "level": "Fluent"})

    squad_status = "Key Player" if (is_starter and p_idx < 4) else ("First Team" if is_starter else "Rotation")

    return {
        "player_name": pname,
        "shirt_number": shirt_num,
        "position_role": role,
        "mass": round(mass, 1),
        "top_speed": round(top_speed, 1),
        "acceleration_time": round(accel, 3),
        "friction_time": frict,
        "turning_penalty": round(turn_pen, 3),
        "sprint_multiplier": sprint_mult,
        "stamina_max": round(stamina, 1),
        "stamina_drain": 18.0,
        "stamina_recover": 9.0,
        "vision": round(vision, 2),
        "composure": round(composure, 2),
        "aggression": aggression,
        "formation_ball_weight": 0.35,
        "close_control": round(close_ctrl, 2),
        "reflexes": round(reflexes, 2),
        "determination": det,
        "work_rate": wr,
        "leadership": lead,
        "temperament": temp,
        "professionalism": prof,
        "ambition": amb,
        "loyalty": loy,
        "adaptability": adapt,
        "traits": 0,
        "player_reputation": rep,
        "wage_weekly": wage,
        "contract_years": random.randint(2, 4),
        "release_clause": 0,
        "squad_status": squad_status,
        "morale": round(random.uniform(0.60, 0.85), 2),
        "market_value": mval,
        "form": form,
        "career_goals": 0,
        "career_assists": 0,
        "last_match_rating": 0.0,
        "is_unavailable": False,
        "nationality": nat,
        "secondary_nationality": "",
        "date_of_birth": dob,
        "spoken_languages": spoken,
        "is_captain": (p_idx == 2),
    }

def generate_staff(team_name, nat, lang):
    roles = [
        ("Assistant Manager", 0.72, 0.68, 0.50, 0.75, 4500),
        ("Head Physio", 0.45, 0.55, 0.85, 0.45, 3800),
        ("Tactical Analyst", 0.55, 0.65, 0.40, 0.82, 3400),
        ("Fitness Coach", 0.78, 0.50, 0.65, 0.50, 3200),
        ("Chief Scout", 0.50, 0.82, 0.40, 0.65, 3600),
    ]
    pool = NAME_POOLS.get(nat, NAME_POOLS["English"])
    out = []
    for s_idx, (role_name, coach, judge, physio, tact, sal) in enumerate(roles):
        first = pool["first"][(s_idx + 4) % len(pool["first"])]
        last = pool["last"][(s_idx * 2 + 5) % len(pool["last"])]
        dob = f"{1975 + s_idx}-04-{10 + s_idx:02d}"
        spoken = [{"language": lang, "proficiency": 1.0, "level": "Native"}]
        if lang != "English":
            spoken.append({"language": "English", "proficiency": 0.75, "level": "Fluent"})
        out.append({
            "staff_name": f"{first} {last}",
            "role": role_name,
            "team_name": team_name,
            "nationality": nat,
            "secondary_nationality": "",
            "date_of_birth": dob,
            "experience": random.randint(15, 30),
            "coaching": coach,
            "judging_ability": judge,
            "physiotherapy": physio,
            "tactical_knowledge": tact,
            "salary_weekly": sal,
            "contract_years": 3,
            "spoken_languages": spoken,
        })
    return out

def generate_manager(team_name, nat, lang, rep):
    pool = NAME_POOLS.get(nat, NAME_POOLS["English"])
    first = pool["first"][random.randint(0, len(pool["first"]) - 1)]
    last = pool["last"][random.randint(0, len(pool["last"]) - 1)]
    mname = f"{first} {last}"
    age = random.randint(42, 63)
    dob = f"{2026 - age}-05-18"
    spoken = [{"language": lang, "proficiency": 1.0, "level": "Native"}]
    if lang != "English":
        spoken.append({"language": "English", "proficiency": 0.80, "level": "Fluent"})
    
    return {
        "name": mname,
        "nationality": nat,
        "experience": random.randint(15, 35),
        "current_team": team_name,
        "reputation": round(clamp(rep + random.uniform(-0.05, 0.05), 0.30, 0.95), 2),
        "board_confidence": 0.70,
        "contract_years": 3,
        "salary_weekly": max(int(rep * 45000), 4000),
        "referee_respect": 0.60,
        "defensive_line": 0.50,
        "tempo": 0.50,
        "width": 0.50,
        "pressing_intensity": 0.55,
        "physicality": 0.55,
        "preferred_formation": random.choice(FORMATIONS),
        "attacking_formation": "4-3-3",
        "defensive_formation": "5-3-2",
        "youth_trust": 0.55,
        "loyalty_bias": 0.60,
        "form_sensitivity": 0.50,
        "preferred_min_age": 20,
        "preferred_max_age": 32,
        "budget_flexibility": 0.40,
        "preferred_mass_min": 70.0,
        "preferred_mass_max": 90.0,
        "prized_attribute": random.choice(["vision", "composure", "aggression"]),
        "preferred_playstyle": random.choice(["technical", "physical", "pace", "aerial", "engine"]),
        "traits": 3,
        "matches_managed": 120,
        "wins": 55,
        "draws": 30,
        "losses": 35,
        "date_of_birth": dob,
        "spoken_languages": spoken,
    }

def generate_world():
    os.makedirs(SHARDS_DIR, exist_ok=True)

    all_divisions = []
    all_managers = []
    all_staff = []
    all_referees = []

    club_idx_global = 0

    for n_data in NATIONS_DATA:
        nat = n_data["nation"]
        key = n_data["key"]
        confed = n_data["confed"]
        lang = n_data["lang"]
        lname = n_data["league_name"]
        count = n_data["team_count"]
        releg = n_data["relegation_slots"]
        cities = n_data["cities"]
        suffixes = CLUBS_SUFFIXES.get(nat, ["FC", "United", "City"])

        division_teams = []
        division_stubs = []

        print(f"Generating {lname} ({nat}) - {count} clubs...")

        for i in range(count):
            city = cities[i % len(cities)]
            suffix = suffixes[i % len(suffixes)]
            
            # Formatting name
            if suffix in ["Real", "Atletico", "Deportivo", "Sporting", "Inter", "Olympique", "Borussia", "Eintracht"]:
                team_name = f"{suffix} {city}"
            elif suffix in ["CF", "FC", "AC", "AS", "FK", "SK", "BK", "IF"]:
                team_name = f"{city} {suffix}"
            else:
                team_name = f"{city} {suffix}"

            # Ensure uniqueness
            if any(t["team_name"] == team_name for t in division_teams):
                team_name = f"{city} {suffix} {i + 1}"

            rep_rank = 1.0 - (float(i) / max(float(count - 1), 1.0))
            rep = round(clamp(n_data["base_rep"] - (1.0 - rep_rank) * n_data["rep_spread"] + random.uniform(-0.03, 0.03), 0.35, 0.95), 2)
            stature = get_stature(rep)

            transfer_budget = int(rep * 80000000 * random.uniform(0.6, 1.4) / 100000) * 100000
            wage_budget = max(int(transfer_budget * 0.015 / 1000) * 1000, 35000)

            pri_c, sec_c = PALETTES[i % len(PALETTES)]

            squad = []
            for p_idx in range(18):
                role = SQUAD_ROLES[p_idx]
                p = generate_player(p_idx, role, nat, lang, team_name, rep)
                squad.append(p)

            lineup = list(range(11))
            staff = generate_staff(team_name, nat, lang)
            mgr = generate_manager(team_name, nat, lang, rep)
            all_managers.append(mgr)
            all_staff.extend(staff)

            team_obj = {
                "team_name": team_name,
                "reputation": rep,
                "stature": stature,
                "transfer_budget": transfer_budget,
                "wage_budget_weekly": wage_budget,
                "team_color": pri_c,
                "secondary_color": sec_c,
                "gk_color": [0.15, 0.88, 0.45],
                "formation": mgr["preferred_formation"],
                "stadium_name": f"{city} Stadium",
                "stadium_capacity": int(rep * 65000 + 10000),
                "lineup_indices": lineup,
                "squad": squad,
                "staff": staff
            }

            division_teams.append(team_obj)

            stub_obj = {
                "team_name": team_name,
                "reputation": rep,
                "stature": stature,
                "transfer_budget": transfer_budget,
                "wage_budget_weekly": wage_budget,
                "primary_color": f"#{int(pri_c[0]*255):02x}{int(pri_c[1]*255):02x}{int(pri_c[2]*255):02x}",
                "secondary_color": f"#{int(sec_c[0]*255):02x}{int(sec_c[1]*255):02x}{int(sec_c[2]*255):02x}",
                "formation": mgr["preferred_formation"]
            }
            division_stubs.append(stub_obj)
            club_idx_global += 1

        shard_rel = f"shards/{key}_t1.json"
        shard_path = os.path.join(DATA_DIR, shard_rel)

        # Write shard file
        with open(shard_path, "w", encoding="utf-8") as sf:
            json.dump({"division": lname, "nation": nat, "teams": division_teams}, sf, indent=2)

        all_divisions.append({
            "name": lname,
            "nation": nat,
            "confederation": confed,
            "tier_index": 1,
            "group_index": None,
            "team_count": count,
            "promotion_slots": 0,
            "relegation_slots": releg,
            "shard": shard_rel,
            "teams": division_stubs
        })

    # --- Referees generation ---
    print("Generating international referees...")
    ref_first = ["Michael", "Antonio", "Felix", "Clement", "Bjorn", "Daniele", "Szymon", "Slavko", "Wilmar", "Fernando", "Facundo", "Mark", "Chris", "Artur", "Halil", "Sergei", "Cesar", "Ismail", "Yoshimi", "Danny"]
    ref_last = ["Oliver", "Mateu", "Zwayer", "Turpin", "Kuipers", "Orsato", "Marciniak", "Vincic", "Roldan", "Rapallini", "Tello", "Geiger", "Kavanagh", "Soares", "Umut", "Karasev", "Ramos", "Elfath", "Yamashita", "Makkelie"]
    for r_i in range(24):
        nat_spec = NATIONS_DATA[r_i % len(NATIONS_DATA)]
        r_nat = nat_spec["nation"]
        r_lang = nat_spec["lang"]
        rname = f"{ref_first[r_i % len(ref_first)]} {ref_last[r_i % len(ref_last)]}"
        all_referees.append({
            "name": rname,
            "nationality": r_nat,
            "date_of_birth": f"{1980 + (r_i % 12)}-0{1 + (r_i % 9)}-15",
            "experience": random.randint(12, 35),
            "strictness": round(random.uniform(0.35, 0.85), 2),
            "consistency": round(random.uniform(0.60, 0.95), 2),
            "composure": round(random.uniform(0.60, 0.95), 2),
            "unprofessionalism": round(random.uniform(0.02, 0.20), 2),
            "incoherence": round(random.uniform(0.02, 0.20), 2),
            "reputation": round(random.uniform(0.65, 0.95), 2),
            "respect_rating": round(random.uniform(0.60, 0.92), 2),
            "matches_officiated": random.randint(80, 250),
            "fouls_awarded": random.randint(1200, 4000),
            "penalties_awarded": random.randint(20, 80),
            "yellow_cards": random.randint(250, 800),
            "red_cards": random.randint(10, 40),
            "spoken_languages": [
                {"language": r_lang, "proficiency": 1.0, "level": "Native"},
                {"language": "English", "proficiency": 0.85, "level": "Fluent"}
            ]
        })

    # Write world_manifest.json
    manifest_path = os.path.join(DATA_DIR, "world_manifest.json")
    print(f"Writing manifest to {manifest_path}...")
    with open(manifest_path, "w", encoding="utf-8") as mf:
        json.dump({
            "league_name": "PowerFootball World League Pyramid",
            "version": "1.0",
            "total_teams": club_idx_global,
            "divisions": all_divisions
        }, mf, indent=2)

    # Write managers and referees
    with open(os.path.join(DATA_DIR, "world_managers.json"), "w", encoding="utf-8") as mf:
        json.dump({"managers": all_managers}, mf, indent=2)

    with open(os.path.join(DATA_DIR, "world_referees.json"), "w", encoding="utf-8") as rf:
        json.dump({"referees": all_referees}, rf, indent=2)

    print(f"\n[DONE] Generated {len(all_divisions)} leagues, {club_idx_global} clubs, {club_idx_global * 18} players.")
    print(f"[DONE] Generated {len(all_managers)} managers, {len(all_referees)} referees, {len(all_staff)} staff.")

if __name__ == "__main__":
    generate_world()
