import 'package:flutter/material.dart';
import 'member_detail_screen.dart';

class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  final List<Map<String, String>> members = const [
    {
      'name': 'Faheem',
      'role': 'Full Stack Developer',
      'desc': 'The Lead Architect and Visionary behind the Mofa Utility Suite. Faheem specializes in bridging the gap between high-performance backends and intuitive mobile experiences, ensuring every line of code serves a purpose.',
      'ig': '@smart_faheem24x7',
      'ig_url': 'https://www.instagram.com/smart_faheem24x7/',
      'image': 'assets/images/members/faheem.jpg',
      'is_local': 'true',
    },
    {
      'name': 'Nafeez',
      'role': 'Graphic Designer',
      'desc': 'A Creative Visionary who defines the visual soul of FNNSR. Nafeez focuses on high-impact digital aesthetics and intuitive UI/UX, transforming complex ideas into stunning, user-friendly visual narratives.',
      'ig': '@nafeez_4evr',
      'ig_url': 'https://www.instagram.com/nafeez_4evr/',
      'image': 'assets/images/members/nafeez.png',
      'is_local': 'true',
    },
    {
      'name': 'Shahid',
      'role': 'Corporate Secretary',
      'desc': 'The Organizational Backbone of FNNSR. Shahid ensures the team operates with maximum efficiency, handling legal coordination, administrative excellence, and strategic management with precision.',
      'ig': '@__sha__hi_d',
      'ig_url': 'https://www.instagram.com/__sha__hi_d/',
      'image': 'assets/images/members/shahid.png',
      'is_local': 'true',
    },
    {
      'name': 'Nihal',
      'role': 'Traveler',
      'desc': 'A Global Explorer bringing a world of perspective to FNNSR. Nihal bridges cultures and captures unique stories from across the globe, enriching our creative process with adventurous spirit and diverse insights.',
      'ig': '@lahin_03',
      'ig_url': 'https://www.instagram.com/lahin_03/',
      'image': 'assets/images/members/nihal.jpg',
      'is_local': 'true',
    },
    {
      'name': 'Reehan',
      'role': 'Editor',
      'desc': 'The Master of Post-Production. Reehan possesses a unique ability to weave raw footage into compelling digital masterpieces, using advanced editing techniques to tell stories that resonate with viewers.',
      'ig': '@rehan_khan._.03',
      'ig_url': 'https://www.instagram.com/rehan_khan._.03/',
      'image': 'assets/images/members/reehan.jpg',
      'is_local': 'true',
    },
    {
      'name': 'Naveed',
      'role': 'Content Creator',
      'desc': 'A Digital Storyteller dedicated to the art of engagement. Naveed crafts innovative content that captures the imagination of global audiences, driving brand awareness through viral and impactful media.',
      'ig': '@naveed__ahmed__',
      'ig_url': 'https://www.instagram.com/naveed__ahmed__/',
      'image': 'assets/images/members/naveed.jpg',
      'is_local': 'true',
    },
    {
      'name': 'Azhaan',
      'role': 'Digital Marketer',
      'desc': 'A Growth Strategist leveraging data-driven insights. Azhaan expands our digital footprint through high-impact cross-platform campaigns, ensuring FNNSR’s message reaches the right audience at the right time.',
      'ig': '@azhhhhh_11',
      'ig_url': 'https://www.instagram.com/azhhhhh_11/',
      'image': 'assets/images/members/azhaan.jpg',
      'is_local': 'true',
    },
    {
      'name': 'Maaz',
      'role': 'App Developer',
      'desc': 'A Strategic Coordinator focused on streamlining FNNSR\'s workflows. Maaz ensures that every project phase is executed with precision, managing resources and timelines to achieve peak efficiency.',
      'ig': '@maaz_kh',
      'ig_url': 'https://www.instagram.com/maaz_kh/',
      'image': 'https://ui-avatars.com/api/?name=Maaz&background=random&color=fff&size=512',
      'is_local': 'false',
    },
    {
      'name': 'Ubaise',
      'role': 'Software Engineer',
      'desc': 'A Dedicated Problem Solver with a passion for clean, efficient code. bridging complex requirements with elegant and high-performance software solutions.',
      'ig': '@ubaise_ibrahim',
      'ig_url': 'https://www.instagram.com/ubaise_ibrahim/',
      'image': 'assets/images/members/ubaise.jpg',
      'is_local': 'true',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('FNNSR Members'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        itemCount: members.length,
        itemBuilder: (context, index) {
          final member = members[index];
          return _buildMemberCard(context, member);
        },
      ),
    );
  }

  Widget _buildMemberCard(BuildContext context, Map<String, String> member) {
    final bool isLocal = member['is_local'] == 'true';
    final ImageProvider profileImage = isLocal 
        ? AssetImage(member['image']!) as ImageProvider
        : NetworkImage(member['image']!) as ImageProvider;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withOpacity(0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 400),
              pageBuilder: (_, __, ___) => MemberDetailScreen(member: member),
              transitionsBuilder: (_, animation, __, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Hero(
                tag: 'avatar_${member['name']}',
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.indigoAccent.withOpacity(0.3), width: 2),
                    image: DecorationImage(
                      image: profileImage,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member['name']!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      member['role']!,
                      style: const TextStyle(
                        color: Colors.indigoAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      member['ig']!,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }
}
