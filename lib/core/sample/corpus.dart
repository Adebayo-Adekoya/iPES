/// The iPES sample corpus: a personal library of real file formats with
/// gold-standard metadata and judged search queries.
///
/// It serves three purposes: the demo library a new user sees, fixtures for
/// tests, and the evaluation set for spec section 12. All texts were written
/// for this corpus (summaries, not copies, for the public-domain books); all
/// people, organisations and documents are fictional.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../record.dart';
import 'builders.dart';

class Gold {
  const Gold({this.title, this.creator, this.date, this.identifier, this.language, this.ddc, required this.media});
  final String? title;
  final String? creator;

  /// Year ("1813") or full date ("2025-03-01").
  final String? date;

  /// ISBN-13 digits, or "doi:..." for DOIs.
  final String? identifier;
  final String? language;

  /// Correct Dewey class (three digits) as a cataloguer would assign it.
  final String? ddc;
  final MediaType media;
}

class SampleItem {
  SampleItem(this.key, this.fileName, this.bytes, this.gold);
  final String key;
  final String fileName;
  final Uint8List bytes;
  final Gold gold;
}

class JudgedQuery {
  const JudgedQuery(this.query, this.relevance, {this.kind = 'keyword'});
  final String query;

  /// Item key -> graded relevance (2 = highly relevant, 1 = partly relevant).
  final Map<String, int> relevance;

  /// "keyword" when the words appear in the item, "meaning" when they do not.
  final String kind;
}

class SampleCorpus {
  SampleCorpus._();

  static Uint8List _txt(String s) => Uint8List.fromList(utf8.encode(s));

  static List<SampleItem> curated() => [
        // ---------------------------------------------------------------- books
        SampleItem(
          'pride',
          'pride-and-prejudice.epub',
          EpubBuilder.build(
            title: 'Pride and Prejudice',
            creators: ['Jane Austen'],
            date: '1813',
            publisher: 'Project Gutenberg',
            subjects: ['Courtship — Fiction', 'England — Social life and customs — Fiction'],
            chapters: [
              'This novel follows Elizabeth Bennet, the second of five daughters in a country family in England, as she meets the proud and wealthy Mr Darcy. Their first impressions of each other are poor.\n\nThe story turns on manners, marriage and money. Mrs Bennet wants her daughters married well because the family estate will pass to a cousin.',
              'Over the course of the novel Elizabeth learns that her judgement of Darcy was formed by prejudice, and Darcy learns that his pride has hurt others. The book is often read as a comedy of manners and a study of courtship in Regency England.',
            ],
          ),
          const Gold(title: 'Pride and Prejudice', creator: 'Jane Austen', date: '1813', language: 'eng', ddc: '823', media: MediaType.book),
        ),
        SampleItem(
          'frankenstein',
          'frankenstein.epub',
          EpubBuilder.build(
            title: 'Frankenstein; or, The Modern Prometheus',
            creators: ['Mary Shelley'],
            date: '1818',
            publisher: 'Project Gutenberg',
            subjects: ['Science fiction', 'Monsters — Fiction'],
            chapters: [
              'A young scientist, Victor Frankenstein, discovers how to give life to dead matter and builds a creature. Horrified by what he has made, he abandons it.\n\nThe creature, rejected by everyone it meets, turns to revenge against its maker. The novel is told through letters written by an Arctic explorer who meets Victor near the end of his life.',
            ],
          ),
          const Gold(title: 'Frankenstein; or, The Modern Prometheus', creator: 'Mary Shelley', date: '1818', language: 'eng', ddc: '823', media: MediaType.book),
        ),
        SampleItem(
          'souls',
          'du-bois-souls-of-black-folk.epub',
          EpubBuilder.build(
            title: 'The Souls of Black Folk',
            creators: ['W. E. B. Du Bois'],
            date: '1903',
            publisher: 'Project Gutenberg',
            subjects: ['African Americans', 'Race relations'],
            chapters: [
              'A collection of essays on race in the United States after emancipation. The author introduces the idea of double consciousness, the sense of always looking at oneself through the eyes of others.\n\nThe essays cover education, the Freedmen\'s Bureau, the spirituals sung by enslaved people, and the life of a rural community in Georgia.',
            ],
          ),
          const Gold(title: 'The Souls of Black Folk', creator: 'W. E. B. Du Bois', date: '1903', language: 'eng', ddc: '305', media: MediaType.book),
        ),
        SampleItem(
          'equiano',
          'equiano-narrative.epub',
          EpubBuilder.build(
            title: 'The Interesting Narrative of the Life of Olaudah Equiano',
            creators: ['Olaudah Equiano'],
            date: '1789',
            publisher: 'Project Gutenberg',
            subjects: ['Slavery', 'Slave narratives'],
            chapters: [
              'An autobiography by a man who describes being kidnapped as a child in West Africa, enduring the Atlantic crossing on a slave ship, and serving at sea before buying his own freedom.\n\nThe narrative became an important text for the campaign to abolish the slave trade in Britain.',
            ],
          ),
          const Gold(title: 'The Interesting Narrative of the Life of Olaudah Equiano', creator: 'Olaudah Equiano', date: '1789', language: 'eng', ddc: '306', media: MediaType.book),
        ),
        SampleItem(
          'folktales',
          'west-african-folk-tales.epub',
          EpubBuilder.build(
            title: 'West African Folk-Tales',
            creators: ['William H. Barker', 'Cecilia Sinclair'],
            date: '1917',
            publisher: 'Project Gutenberg',
            subjects: ['Folklore — Africa, West', 'Tales'],
            chapters: [
              'A collection of folktales from the Gold Coast and neighbouring lands, many of them about Ananse the spider, who wins by cunning rather than strength.\n\nThe stories explain why things are as they are, such as why the spider lives in the corners of the ceiling, and they are told with proverbs and songs.',
            ],
          ),
          const Gold(title: 'West African Folk-Tales', creator: 'William H. Barker', date: '1917', language: 'eng', ddc: '398', media: MediaType.book),
        ),
        SampleItem(
          'contes',
          'contes-afrique-ouest.epub',
          EpubBuilder.build(
            title: "Contes et légendes de l'Afrique de l'Ouest",
            creators: ['Aminata Diallo'],
            date: '2018',
            language: 'fr',
            publisher: 'Éditions du Sahel',
            isbn: '9789988098766',
            chapters: [
              "Ce recueil rassemble des contes et des légendes racontés le soir dans les villages. Les animaux parlent et le lièvre est souvent plus malin que le lion.\n\nChaque conte se termine par une leçon pour les enfants et pour les adultes qui les écoutent avec eux.",
            ],
          ),
          const Gold(title: "Contes et légendes de l'Afrique de l'Ouest", creator: 'Aminata Diallo', date: '2018', identifier: '9789988098766', language: 'fre', ddc: '398', media: MediaType.book),
        ),
        SampleItem(
          'dsbook',
          'data-structures-in-practice.epub',
          EpubBuilder.build(
            title: 'Data Structures in Practice',
            creators: ['Kwame Asante'],
            date: '2021',
            publisher: 'Accra Tech Press',
            isbn: '9789988012342',
            subjects: ['Data structures (Computer science)', 'Computer programming'],
            chapters: [
              'This book introduces arrays, linked lists, stacks, queues, hash tables, trees and graphs through worked programming examples.\n\nEach chapter ends with exercises. The chapter on hash tables explains collisions, load factor and resizing, and compares open addressing with chaining.',
            ],
          ),
          const Gold(title: 'Data Structures in Practice', creator: 'Kwame Asante', date: '2021', identifier: '9789988012342', language: 'eng', ddc: '005', media: MediaType.book),
        ),
        SampleItem(
          'cookbook',
          'ghanaian-kitchen.epub',
          EpubBuilder.build(
            title: 'Ghanaian Kitchen: Everyday Recipes',
            creators: ['Efua Mensah'],
            date: '2020',
            publisher: 'Tema Home Books',
            isbn: '9789988025670',
            subjects: ['Cooking, Ghanaian'],
            chapters: [
              'Recipes for waakye, kontomire stew, kelewele, light soup and red red, with notes on buying ingredients at the market.\n\nThe introduction explains how to make a pepper base that many of the dishes share, and how to adjust heat for children.',
            ],
          ),
          const Gold(title: 'Ghanaian Kitchen: Everyday Recipes', creator: 'Efua Mensah', date: '2020', identifier: '9789988025670', language: 'eng', ddc: '641', media: MediaType.book),
        ),
        // ------------------------------------------------- papers and reports
        SampleItem(
          'paper',
          'owusu-boateng-2024-metadata.pdf',
          PdfBuilder.build(
            title: 'Mobile-first metadata for personal archives',
            author: 'Ama Owusu',
            creationDate: '2024-05-20',
            keywords: 'metadata; personal archives; mobile',
            pages: [
              'Mobile-first metadata for personal archives\nAma Owusu and Kofi Boateng\nhttps://doi.org/10.5555/ipes.2024.017\n\nPeople keep thousands of files on their phones but describe almost none of them. We study how automatically drafted catalogue records, reviewed by the owner, change how often people find what they look for.',
              'In a two-week diary study, participants who reviewed drafted records found known items faster. We discuss the role of Dublin Core and MARC 21 for personal collections and the risk of trusting automatic metadata without review.',
            ],
          ),
          const Gold(title: 'Mobile-first metadata for personal archives', creator: 'Ama Owusu', date: '2024', identifier: 'doi:10.5555/ipes.2024.017', language: 'eng', ddc: '025', media: MediaType.document),
        ),
        SampleItem(
          'thesis',
          'darko_thesis_final_v3.pdf',
          PdfBuilder.build(
            pages: [
              'Cocoa Yields and Rainfall in the Ashanti Region\nA thesis by Yaw Darko, 2019\n\nThis thesis examines how changes in rainfall affected cocoa yields on smallholder farms between 2005 and 2018. Farm records from forty farmers were compared with weather station data.',
              'Yields fell in years with a long dry season, and farms with shade trees lost less of their harvest. The study recommends shade planting and better access to farm credit.',
            ],
          ),
          const Gold(title: 'Cocoa Yields and Rainfall in the Ashanti Region', creator: 'Yaw Darko', date: '2019', language: 'eng', ddc: '633', media: MediaType.document),
        ),
        SampleItem(
          'algonotes',
          'algorithms-course-reader.pdf',
          PdfBuilder.build(
            title: 'Algorithms: A Course Reader',
            author: 'K. Asamoah',
            creationDate: '2016',
            pages: [
              'Algorithms: A Course Reader\nISBN 0-306-40615-2\n\nSorting, searching and the analysis of running time. The reader covers merge sort, quicksort, binary search and big-O notation with exercises for each lecture.',
            ],
          ),
          const Gold(title: 'Algorithms: A Course Reader', creator: 'K. Asamoah', date: '2016', identifier: '9780306406157', language: 'eng', ddc: '005', media: MediaType.book),
        ),
        // ------------------------------------------------------ household docs
        SampleItem(
          'lease',
          'tenancy_agreement_flat3B.pdf',
          PdfBuilder.build(
            title: 'Tenancy Agreement - Flat 3B, East Legon',
            author: 'Mensah Properties Ltd.',
            creationDate: '2025-03-01',
            pages: [
              'Tenancy Agreement - Flat 3B, East Legon\nThis agreement is made on 1 March 2025 between Mensah Properties Ltd. (the landlord) and the tenant named below.\n\n1. Term. The tenancy runs for two years from 1 March 2025 to 28 February 2027.\n2. Rent. The rent is payable monthly in advance. The rent will be reviewed once a year.',
              '3. Deposit. The tenant pays a deposit equal to two months of rent, returned at the end of the tenancy less the cost of any damage.\n4. Notice. Either party may end this agreement by giving three months written notice to the other party.\n5. Repairs. The landlord is responsible for structural repairs and the tenant for minor repairs.',
            ],
          ),
          const Gold(title: 'Tenancy Agreement - Flat 3B, East Legon', creator: 'Mensah Properties Ltd.', date: '2025-03-01', language: 'eng', ddc: '346', media: MediaType.document),
        ),
        SampleItem(
          'deed',
          'deed_kasoa_2023.pdf',
          PdfBuilder.build(
            title: 'Microsoft Word - deed_final.docx',
            creationDate: '2023-07-12',
            pages: [
              'Deed of Assignment - Plot 14, Kasoa\nThis deed of assignment transfers the leasehold interest in Plot 14 to the assignee for the remainder of the term.\n\nThe plot is shown on the site plan attached. The assignor confirms that the land is free of any other claim and that ground rent has been paid.',
            ],
          ),
          const Gold(title: 'Deed of Assignment - Plot 14, Kasoa', date: '2023-07-12', language: 'eng', ddc: '346', media: MediaType.document),
        ),
        SampleItem(
          'ecg',
          'ecg_receipt_sep2026.pdf',
          PdfBuilder.build(
            title: 'Prepaid Electricity Receipt - September 2026',
            author: 'Electricity Company of Ghana',
            creationDate: '2026-09-14',
            pages: [
              'Prepaid Electricity Receipt - September 2026\nMeter number: [meter]\nAmount paid: GHS 200.00\nUnits purchased: 125.4 kWh\n\nKeep this receipt as proof of payment for your prepaid electricity purchase.',
            ],
          ),
          const Gold(title: 'Prepaid Electricity Receipt - September 2026', creator: 'Electricity Company of Ghana', date: '2026-09-14', language: 'eng', ddc: '363', media: MediaType.document),
        ),
        SampleItem(
          'insurance',
          'motor_policy_schedule.pdf',
          PdfBuilder.build(
            title: 'Motor Insurance Policy Schedule',
            author: 'Star Assurance',
            creationDate: '2025-01-10',
            pages: [
              'Motor Insurance Policy Schedule\nPolicy type: comprehensive cover for a private vehicle.\n\nThe premium is payable yearly. The policy covers accidental damage, fire and theft, and third party injury. The excess is the first GHS 500 of any claim.',
            ],
          ),
          const Gold(title: 'Motor Insurance Policy Schedule', creator: 'Star Assurance', date: '2025-01-10', language: 'eng', ddc: '368', media: MediaType.document),
        ),
        SampleItem(
          'payslip',
          'payslip_2026_08.pdf',
          PdfBuilder.build(
            title: 'Payslip - August 2026',
            author: 'Ghana Health Service',
            creationDate: '2026-08-28',
            pages: [
              'Payslip - August 2026\nEmployee: [name]\nBasic salary: [amount]\nAllowances: [amount]\nSSNIT contribution: [amount]\nIncome tax: [amount]\n\nNet pay is paid into the account on record on the last working day of the month.',
            ],
          ),
          const Gold(title: 'Payslip - August 2026', creator: 'Ghana Health Service', date: '2026-08-28', language: 'eng', ddc: '331', media: MediaType.document),
        ),
        SampleItem(
          'labreport',
          'lab_report_fbc.pdf',
          PdfBuilder.build(
            title: 'Laboratory Report: Full Blood Count',
            author: 'Korle Bu Teaching Hospital',
            creationDate: '2026-05-02',
            pages: [
              'Laboratory Report: Full Blood Count\nPatient: [name]\n\nHaemoglobin, white cell count and platelets are within the reference range. A malaria test was negative. Please discuss these results with your doctor at your next clinic visit.',
            ],
          ),
          const Gold(title: 'Laboratory Report: Full Blood Count', creator: 'Korle Bu Teaching Hospital', date: '2026-05-02', language: 'eng', ddc: '616', media: MediaType.document),
        ),
        SampleItem(
          'schoolreport',
          'Kofi_end_of_term_report.pdf',
          PdfBuilder.build(
            title: 'End of Term Report - Basic 6',
            author: 'Riverside Basic School',
            creationDate: '2026-07-24',
            pages: [
              'End of Term Report - Basic 6\nPupil: Kofi Mensah\n\nKofi has worked hard this term in mathematics and science. His English reading has improved. He should practise his handwriting during the holidays. Conduct: very good.',
            ],
          ),
          const Gold(title: 'End of Term Report - Basic 6', creator: 'Riverside Basic School', date: '2026-07-24', language: 'eng', ddc: '371', media: MediaType.document),
        ),
        SampleItem(
          'tax',
          'GRA_income_tax_return_2025.pdf',
          PdfBuilder.build(
            title: 'Personal Income Tax Return 2025',
            author: 'Ghana Revenue Authority',
            creationDate: '2026-03-31',
            pages: [
              'Personal Income Tax Return 2025\nTaxpayer identification number: [TIN]\n\nThis return declares employment income and tax already deducted by the employer for the year 2025. Any balance due must be paid by the filing deadline.',
            ],
          ),
          const Gold(title: 'Personal Income Tax Return 2025', creator: 'Ghana Revenue Authority', date: '2026-03-31', language: 'eng', ddc: '336', media: MediaType.document),
        ),
        SampleItem(
          'warranty',
          'warranty_RF210.pdf',
          PdfBuilder.build(
            title: 'Warranty Certificate - Refrigerator RF-210',
            author: 'Nasco Electronics',
            creationDate: '2024-11-02',
            pages: [
              'Warranty Certificate - Refrigerator RF-210\nThe compressor is covered for five years and other parts for two years from the date of purchase.\n\nThe warranty does not cover damage from power surges. Keep the purchase receipt with this certificate.',
            ],
          ),
          const Gold(title: 'Warranty Certificate - Refrigerator RF-210', creator: 'Nasco Electronics', date: '2024-11-02', language: 'eng', ddc: '643', media: MediaType.document),
        ),
        SampleItem(
          'bank',
          'statement_mar_2026.pdf',
          PdfBuilder.build(
            title: 'Account Statement - March 2026',
            author: 'GCB Bank',
            creationDate: '2026-04-01',
            pages: [
              'Account Statement - March 2026\nAccount type: savings\n\nOpening balance, deposits, withdrawals and closing balance for the period 1 March 2026 to 31 March 2026. Interest earned this month has been added to the account.',
            ],
          ),
          const Gold(title: 'Account Statement - March 2026', creator: 'GCB Bank', date: '2026-04-01', language: 'eng', ddc: '332', media: MediaType.document),
        ),
        SampleItem(
          'church',
          'harvest_programme_2025.pdf',
          PdfBuilder.build(
            title: 'Order of Service - Harvest Thanksgiving 2025',
            author: 'Calvary Methodist Church',
            creationDate: '2025-10-19',
            pages: [
              'Order of Service - Harvest Thanksgiving 2025\nOpening hymn, prayer, Bible readings, sermon, harvest offering and auction of farm produce, closing prayer.\n\nAll are welcome to the thanksgiving lunch after the service.',
            ],
          ),
          const Gold(title: 'Order of Service - Harvest Thanksgiving 2025', creator: 'Calvary Methodist Church', date: '2025-10-19', language: 'eng', ddc: '264', media: MediaType.document),
        ),
        // ----------------------------------------------------------- text notes
        SampleItem(
          'jollof',
          'jollof-rice.md',
          _txt('# Jollof Rice (Ghana style)\n\nBy Auntie Esi, 2024\n\nIngredients: rice, tomatoes, onions, pepper, tomato paste, oil, stock and spices.\n\nFry the onions, add the blended tomatoes and pepper and cook down until the oil rises. Add stock and washed rice, cover tightly and cook on low heat until the rice is soft. Serve with fried chicken or fish.'),
          const Gold(title: 'Jollof Rice (Ghana style)', creator: 'Auntie Esi', date: '2024', language: 'eng', ddc: '641', media: MediaType.document),
        ),
        SampleItem(
          'groundnut',
          'groundnut_soup.txt',
          _txt('Groundnut Soup with Chicken\n\nA family recipe. Boil the chicken with onion and ginger. Stir in groundnut paste mixed with water and simmer for forty minutes until the oil comes to the top. Add tomatoes and pepper. Serve with rice balls or fufu.'),
          const Gold(title: 'Groundnut Soup with Chicken', language: 'eng', ddc: '641', media: MediaType.document),
        ),
        SampleItem(
          'lecturenotes',
          'CSCD201_lecture6_notes.md',
          _txt('# Lecture 6 Notes: Stacks, Queues and Hash Tables\n\nBy Dr. K. Asamoah, 2026-09-21\n\nA stack is last in, first out. A queue is first in, first out. A hash table maps keys to buckets with a hash function; when two keys share a bucket we have a collision.\n\nExam tip: be able to explain the load factor and when to resize the table.'),
          const Gold(title: 'Lecture 6 Notes: Stacks, Queues and Hash Tables', creator: 'Dr. K. Asamoah', date: '2026-09-21', language: 'eng', ddc: '005', media: MediaType.document),
        ),
        SampleItem(
          'cv',
          'CV_Ama_Owusu.md',
          _txt('# Curriculum Vitae - Ama Owusu\n\nLibrarian and information specialist with eight years of experience in cataloguing, digital archives and training.\n\nEmployment: University library, systems librarian. Education: MA Information Studies. Skills: MARC 21, Dublin Core, records management.'),
          const Gold(title: 'Curriculum Vitae - Ama Owusu', language: 'eng', ddc: '650', media: MediaType.document),
        ),
        SampleItem(
          'reunion',
          'compte_rendu_reunion_parents.txt',
          _txt("Compte rendu de la réunion de l'association des parents\n\nLa réunion a eu lieu le 12 mai 2025 à l'école. Les parents ont discuté des frais de transport, de la cantine et de la fête de fin d'année. Le bureau va écrire au directeur pour demander une date pour la prochaine réunion."),
          const Gold(title: "Compte rendu de la réunion de l'association des parents", language: 'fre', ddc: '371', media: MediaType.document),
        ),
        SampleItem(
          'football',
          'hearts_vs_kotoko_notes.txt',
          _txt('Hearts of Oak vs Kotoko - match notes\n\nThe derby ended in a two all draw at the Accra Sports Stadium. Both goals for Hearts came from set pieces. The second half was much better than the first and the crowd stayed until the final whistle.'),
          const Gold(title: 'Hearts of Oak vs Kotoko - match notes', language: 'eng', ddc: '796', media: MediaType.document),
        ),
        // ---------------------------------------------------------------- audio
        SampleItem(
          'lectureaudio',
          'lecture06.mp3',
          Mp3Builder.build(title: 'Lecture 6: Data Structures', artist: 'Dr. K. Asamoah', album: 'CSCD 201', year: '2026', genre: 'Speech', language: 'eng'),
          const Gold(title: 'Lecture 6: Data Structures', creator: 'Dr. K. Asamoah', date: '2026', language: 'eng', ddc: '005', media: MediaType.audio),
        ),
        SampleItem(
          'song',
          'sweet_mother_accra.mp3',
          Mp3Builder.build(title: 'Sweet Mother Accra', artist: 'Kwesi Ampah Band', album: 'Highlife Evenings', year: '2019', genre: 'Highlife'),
          const Gold(title: 'Sweet Mother Accra', creator: 'Kwesi Ampah Band', date: '2019', ddc: '781', media: MediaType.audio),
        ),
        SampleItem(
          'podcast',
          'farming_today_cocoa_prices.mp3',
          Mp3Builder.build(title: 'Farming Today: Cocoa Prices', artist: 'Agri Radio Ghana', year: '2025', genre: 'Podcast'),
          const Gold(title: 'Farming Today: Cocoa Prices', creator: 'Agri Radio Ghana', date: '2025', ddc: '633', media: MediaType.audio),
        ),
        SampleItem(
          'voicenote',
          'AUD-20260310-WA0003.mp3',
          Mp3Builder.build(),
          const Gold(date: '2026-03-10', media: MediaType.audio),
        ),
        // ---------------------------------------------------------------- video
        SampleItem('naming', 'VID_20240615_101500.mp4', Mp4Builder.build(seed: 1),
            const Gold(date: '2024-06-15', media: MediaType.video)),
        SampleItem('wedding', 'Ama and Kofi wedding (2023).mp4', Mp4Builder.build(seed: 2),
            const Gold(title: 'Ama and Kofi Wedding', date: '2023', ddc: '392', media: MediaType.video)),
        SampleItem('birthday', 'Grandma Akosua - 80th birthday (2022).mp4', Mp4Builder.build(seed: 3),
            const Gold(title: 'Grandma Akosua 80th birthday', date: '2022', ddc: '392', media: MediaType.video)),
        // ---------------------------------------------------------------- photos
        SampleItem('xmas', 'IMG_20191225_143000.jpg', JpegBuilder.build(dateTimeOriginal: '2019:12:25 14:30:00'),
            const Gold(date: '2019-12-25', media: MediaType.image)),
        SampleItem('beach', 'PXL_20250801_090000.jpg', JpegBuilder.build(dateTimeOriginal: '2025:08:01 09:00:00'),
            const Gold(date: '2025-08-01', media: MediaType.image)),
        SampleItem('grandma', 'Grandma at Christmas 2019.jpg', JpegBuilder.build(dateTimeOriginal: '2019:12:25 16:05:00'),
            const Gold(title: 'Grandma at Christmas 2019', date: '2019-12-25', media: MediaType.image)),
      ];

  /// Judged queries for search evaluation. "meaning" queries use words that
  /// do not appear in the relevant items, so only meaning-based ranking can
  /// find them.
  static const queries = <JudgedQuery>[
    JudgedQuery('what does my lease say about notice', {'lease': 2}),
    JudgedQuery('tenancy agreement', {'lease': 2, 'deed': 1}),
    JudgedQuery('rent deposit', {'lease': 2}),
    JudgedQuery('electricity receipt', {'ecg': 2}),
    JudgedQuery('jollof', {'jollof': 2}),
    JudgedQuery('recipes', {'jollof': 2, 'groundnut': 2, 'cookbook': 2}),
    JudgedQuery('data structures lecture', {'lecturenotes': 2, 'lectureaudio': 2, 'dsbook': 1}),
    JudgedQuery('hash tables', {'lecturenotes': 2, 'dsbook': 2, 'lectureaudio': 1}),
    JudgedQuery('videos from 2024', {'naming': 2}),
    JudgedQuery('wedding video', {'wedding': 2}),
    JudgedQuery('photos of grandma', {'grandma': 2, 'birthday': 1}),
    JudgedQuery('austen', {'pride': 2}),
    JudgedQuery('folk tales', {'folktales': 2, 'contes': 1}),
    JudgedQuery('cocoa', {'thesis': 2, 'podcast': 2}),
    JudgedQuery('full blood count', {'labreport': 2}),
    JudgedQuery('insurance policy', {'insurance': 2}),
    JudgedQuery('tax return', {'tax': 2}),
    JudgedQuery('bank statement march', {'bank': 2}),
    JudgedQuery('end of term report', {'schoolreport': 2}),
    JudgedQuery('highlife', {'song': 2}),
    JudgedQuery('metadata personal archives', {'paper': 2}),
    JudgedQuery('slave narrative', {'equiano': 2, 'souls': 1}),
    JudgedQuery('frankenstein', {'frankenstein': 2}),
    JudgedQuery('réunion des parents', {'reunion': 2}),
    JudgedQuery('harvest thanksgiving', {'church': 2}),
    JudgedQuery('9780306406157', {'algonotes': 2}),
    // Vocabulary mismatch: the words below are not in the relevant items.
    JudgedQuery('power bill', {'ecg': 2}, kind: 'meaning'),
    JudgedQuery('cooking', {'jollof': 2, 'groundnut': 2, 'cookbook': 2}, kind: 'meaning'),
    JudgedQuery('marriage', {'wedding': 2}, kind: 'meaning'),
    JudgedQuery('farming', {'thesis': 2, 'podcast': 2}, kind: 'meaning'),
    JudgedQuery('hospital test results', {'labreport': 2}, kind: 'meaning'),
    JudgedQuery('car cover', {'insurance': 2}, kind: 'meaning'),
    JudgedQuery('my salary', {'payslip': 2}, kind: 'meaning'),
    JudgedQuery('music', {'song': 2}, kind: 'meaning'),
    JudgedQuery('when must I quit the flat', {'lease': 2}, kind: 'meaning'),
    JudgedQuery('fridge guarantee', {'warranty': 2}, kind: 'meaning'),
    JudgedQuery('land papers', {'deed': 2, 'lease': 1}, kind: 'meaning'),
    JudgedQuery('my resume', {'cv': 2}, kind: 'meaning'),
  ];

  // -------------------------------------------------------------------------
  // Generated items: larger, varied set for cataloguing accuracy.

  static const _first = ['Kwame', 'Ama', 'Kofi', 'Efua', 'Yaw', 'Akosua', 'Kojo', 'Abena', 'Kwesi', 'Adwoa', 'Fiifi', 'Esi', 'Nana', 'Selorm', 'Ibrahim', 'Fatima', 'Chidi', 'Ngozi', 'John', 'Mary'];
  static const _last = ['Mensah', 'Owusu', 'Boateng', 'Asante', 'Darko', 'Appiah', 'Ofori', 'Addo', 'Agyeman', 'Quaye', 'Tetteh', 'Amoah', 'Sarpong', 'Danso', 'Okafor', 'Bello', 'Smith', 'Adjei'];
  static const _topics = [
    ('Introduction to Soil Science', '631', 'Soil, crops and farming practice for smallholder farms.'),
    ('A Short History of the Gold Coast', '966', 'The history of the Gold Coast from early kingdoms to independence.'),
    ('Practical Python Programming', '005', 'Programming with Python, from variables to data structures and testing.'),
    ('Understanding Contracts', '346', 'How contracts, leases and agreements work in everyday life.'),
    ('Healthy Eating for Families', '641', 'Cooking simple meals with local food and fresh ingredients.'),
    ('Basic Statistics', '519', 'Mean, median, variance and the statistics of samples.'),
    ('Highlife Music and Its Makers', '781', 'The story of highlife music, its bands and its songs.'),
    ('Primary Health Care', '362', 'Clinics, community health workers and access to medicine.'),
    ('Teaching Reading in Basic Schools', '372', 'Methods for teaching children to read in school.'),
    ('Small Business Management', '658', 'Running a small business: sales, marketing and records.'),
    ('Poems of the Coast', '821', 'A collection of poems about the sea, fishing and family.'),
    ('Personal Finance Basics', '332', 'Savings, loans, interest and planning a household budget.'),
  ];

  /// [count] files across formats, with randomised metadata quality.
  static List<SampleItem> generated({int count = 150, int seed = 7}) {
    final rnd = Random(seed);
    String pick(List<String> l) => l[rnd.nextInt(l.length)];
    final items = <SampleItem>[];
    for (var i = 0; i < count; i++) {
      final author = '${pick(_first)} ${pick(_last)}';
      final topic = _topics[rnd.nextInt(_topics.length)];
      final year = (1995 + rnd.nextInt(31)).toString();
      final title = rnd.nextBool() ? topic.$1 : '${topic.$1}, Volume ${1 + rnd.nextInt(3)}';
      final body = '${topic.$3} This edition by $author was prepared for readers who want a clear introduction. '
          'Each chapter has examples and questions for practice. ${topic.$3}';
      final slug = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      final kind = rnd.nextInt(6);
      switch (kind) {
        case 0: // EPUB with full metadata, sometimes an ISBN.
          final isbn = rnd.nextBool() ? _isbn(rnd) : null;
          items.add(SampleItem('gen$i', '$slug.epub',
              EpubBuilder.build(title: title, creators: [author], date: year, publisher: 'Sample Press', isbn: isbn, chapters: [body]),
              Gold(title: title, creator: author, date: year, identifier: isbn, language: 'eng', ddc: topic.$2, media: MediaType.book)));
        case 1: // PDF with Info dictionary.
          items.add(SampleItem('gen$i', '$slug.pdf',
              PdfBuilder.build(title: title, author: author, creationDate: year, pages: [title, body]),
              Gold(title: title, creator: author, date: year, language: 'eng', ddc: topic.$2, media: MediaType.document)));
        case 2: // PDF without metadata: title on the first line, ISBN in text.
          final isbn = _isbn(rnd);
          items.add(SampleItem('gen$i', 'scan_${1000 + i}.pdf',
              PdfBuilder.build(pages: ['$title\nby $author\nISBN $isbn\n\n$body']),
              Gold(title: title, creator: author, identifier: isbn, language: 'eng', ddc: topic.$2, media: MediaType.book)));
        case 3: // "Author - Title (Year).pdf" with a junk embedded title.
          items.add(SampleItem('gen$i', '$author - $title ($year).pdf',
              PdfBuilder.build(title: 'Microsoft Word - draft$i.docx', pages: [body]),
              Gold(title: title, creator: author, date: year, language: 'eng', ddc: topic.$2, media: MediaType.document)));
        case 4: // Plain text notes.
          items.add(SampleItem('gen$i', '$slug.txt', _txt('$title\n\n$body'),
              Gold(title: title, language: 'eng', ddc: topic.$2, media: MediaType.document)));
        default: // MP3 with tags.
          items.add(SampleItem('gen$i', '$slug.mp3',
              Mp3Builder.build(title: title, artist: author, year: year),
              Gold(title: title, creator: author, date: year, media: MediaType.audio)));
      }
    }
    return items;
  }

  static String _isbn(Random rnd) {
    final digits = '97899880${List.generate(4, (_) => rnd.nextInt(10)).join()}';
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(digits[i]) * (i.isEven ? 1 : 3);
    }
    return '$digits${(10 - sum % 10) % 10}';
  }
}
