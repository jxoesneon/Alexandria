import 'package:flutter/material.dart';
import '../widgets/glass_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _selectedCategory = 'All';
  final _categories = const [
    'All',
    'Books',
    'Science',
    'Audio',
    '3D Models',
    'Datasets',
    'Web Archives'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Library'),
      ),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by title, author, topic, or CID...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.tune),
                  tooltip: 'Filter Options',
                  onPressed: () {},
                ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Category Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              children: _categories.map((cat) {
                final isSelected = cat == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() => _selectedCategory = cat);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: const [
                GlassCard(
                  child: ListTile(
                    leading: Icon(Icons.picture_as_pdf),
                    title: Text('Relativity: The Special and General Theory'),
                    subtitle: Text('Albert Einstein • Physics (PDF)'),
                    trailing: Icon(Icons.arrow_forward_ios, size: 14),
                  ),
                ),
                SizedBox(height: 10),
                GlassCard(
                  child: ListTile(
                    leading: Icon(Icons.audiotrack),
                    title: Text('Symphony No. 9 in D minor'),
                    subtitle: Text('Ludwig van Beethoven • Audio (FLAC)'),
                    trailing: Icon(Icons.arrow_forward_ios, size: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
