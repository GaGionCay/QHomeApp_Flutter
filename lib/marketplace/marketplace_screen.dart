import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../auth/token_storage.dart';
import 'marketplace_view_model.dart';
import 'marketplace_service.dart';
import '../models/marketplace_post.dart';
import '../models/marketplace_category.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';
import 'image_viewer_screen.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  late final MarketplaceViewModel _viewModel;
  final ScrollController _scrollController = ScrollController();
  final TokenStorage _tokenStorage = TokenStorage();
  String? _currentResidentId;

  @override
  void initState() {
    super.initState();
    final service = MarketplaceService();
    final storage = TokenStorage();
    _viewModel = MarketplaceViewModel(service, storage);
    _viewModel.initialize();
    _scrollController.addListener(_onScroll);
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    _currentResidentId = await _tokenStorage.readResidentId();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Load more when user scrolls to 80% of the list
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_viewModel.isLoadingMore && _viewModel.hasMore) {
        _viewModel.loadMore();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: const Text('Chợ cư dân'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            // Đăng bài button
            IconButton(
              icon: Icon(
                CupertinoIcons.add_circled,
                color: theme.colorScheme.primary,
              ),
              onPressed: () async {
                final result = await Navigator.push<MarketplacePost>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreatePostScreen(),
                  ),
                );
                
                // Refresh posts if a new post was created
                if (result != null && mounted) {
                  _viewModel.refresh();
                }
              },
              tooltip: 'Đăng bài',
            ),
            // Filter button
            Consumer<MarketplaceViewModel>(
              builder: (context, viewModel, child) {
                return IconButton(
                  icon: Stack(
                    children: [
                      Icon(
                        CupertinoIcons.slider_horizontal_3,
                        color: theme.colorScheme.onSurface,
                      ),
                      // Badge to show active filters
                      if (viewModel.selectedCategory != null || viewModel.sortBy != null)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onPressed: () => _showFilterBottomSheet(context, viewModel),
                  tooltip: 'Bộ lọc',
                );
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(96), // Increased for filter badges
            child: Column(
              children: [
                Consumer<MarketplaceViewModel>(
                  builder: (context, viewModel, child) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: false,
                            label: Text('Building của tôi'),
                            icon: Icon(CupertinoIcons.building_2_fill, size: 16),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('Tất cả'),
                            icon: Icon(CupertinoIcons.globe, size: 16),
                          ),
                        ],
                        selected: {viewModel.showAllBuildings},
                        onSelectionChanged: (Set<bool> selected) {
                          if (selected.isNotEmpty) {
                            viewModel.setShowAllBuildings(selected.first);
                          }
                        },
                        style: SegmentedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    );
                  },
                ),
                // Filter badges
                Consumer<MarketplaceViewModel>(
                  builder: (context, viewModel, child) {
                    if (viewModel.selectedCategory == null && viewModel.sortBy == null) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          if (viewModel.selectedCategory != null)
                            _buildFilterChip(
                              context,
                              theme,
                              _getCategoryName(viewModel.selectedCategory!, viewModel.categories),
                              () => viewModel.setCategoryFilter(null),
                            ),
                          if (viewModel.sortBy != null)
                            _buildFilterChip(
                              context,
                              theme,
                              _getSortByLabel(viewModel.sortBy!),
                              () => viewModel.setSortBy(null),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        body: Consumer<MarketplaceViewModel>(
          builder: (context, viewModel, child) {
            if (viewModel.isLoading && viewModel.posts.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (viewModel.error != null && viewModel.posts.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.exclamationmark_triangle,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      viewModel.error!,
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => viewModel.refresh(),
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              );
            }

            if (viewModel.posts.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.shopping_cart,
                      size: 64,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Chưa có bài đăng nào',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () => viewModel.refresh(),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                // Use key to preserve scroll position when items are added
                key: const PageStorageKey<String>('marketplace_posts_list'),
                cacheExtent: 500, // Cache items outside viewport for smoother scrolling
                itemCount: viewModel.posts.length + 
                          (viewModel.isLoadingMore ? 1 : 0) + 
                          (!viewModel.hasMore && viewModel.posts.isNotEmpty ? 1 : 0),
                itemBuilder: (context, index) {
                  // Show loading indicator at the end when loading more
                  if (index == viewModel.posts.length && viewModel.isLoadingMore) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  
                  // Show "No more posts" indicator
                  if (index == viewModel.posts.length && !viewModel.hasMore) {
                    return Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: Text(
                          'Không còn bài viết nào nữa',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    );
                  }

                  final post = viewModel.posts[index];
                  // Use stable key to preserve scroll position
                  return _PostCard(
                    key: ValueKey(post.id),
                    post: post,
                    currentResidentId: _currentResidentId,
                    categories: viewModel.categories,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChangeNotifierProvider.value(
                            value: viewModel,
                            child: PostDetailScreen(post: post),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  void _showFilterBottomSheet(BuildContext context, MarketplaceViewModel viewModel) {
    final theme = Theme.of(context);
    String? selectedCategory = viewModel.selectedCategory;
    String? selectedSortBy = viewModel.sortBy;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom,
              top: 20,
              left: 20,
              right: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Bộ lọc',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        // Clear all filters
                        setState(() {
                          selectedCategory = null;
                          selectedSortBy = null;
                        });
                        viewModel.setCategoryFilter(null);
                        viewModel.setSortBy(null);
                      },
                      child: const Text('Xóa tất cả'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Category Filter
                Text(
                  'Danh mục',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // "Tất cả" option
                    ChoiceChip(
                      label: const Text('Tất cả'),
                      selected: selectedCategory == null,
                      onSelected: (selected) {
                        setState(() {
                          selectedCategory = null;
                        });
                        viewModel.setCategoryFilter(null);
                      },
                    ),
                    // Category options
                    ...viewModel.categories
                        .where((cat) => cat.active)
                        .map((category) => ChoiceChip(
                              label: Text(category.name),
                              selected: selectedCategory == category.code,
                              onSelected: (selected) {
                                setState(() {
                                  selectedCategory = selected ? category.code : null;
                                });
                                viewModel.setCategoryFilter(selected ? category.code : null);
                              },
                            )),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Price Sort
                Text(
                  'Sắp xếp theo giá',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Mặc định'),
                      selected: selectedSortBy == null,
                      onSelected: (selected) {
                        setState(() {
                          selectedSortBy = null;
                        });
                        viewModel.setSortBy(null);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Giá: Thấp → Cao'),
                      selected: selectedSortBy == 'price_asc',
                      onSelected: (selected) {
                        setState(() {
                          selectedSortBy = selected ? 'price_asc' : null;
                        });
                        viewModel.setSortBy(selected ? 'price_asc' : null);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Giá: Cao → Thấp'),
                      selected: selectedSortBy == 'price_desc',
                      onSelected: (selected) {
                        setState(() {
                          selectedSortBy = selected ? 'price_desc' : null;
                        });
                        viewModel.setSortBy(selected ? 'price_desc' : null);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(BuildContext context, ThemeData theme, String label, VoidCallback onRemove) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(label),
        onDeleted: onRemove,
        deleteIcon: const Icon(CupertinoIcons.xmark_circle_fill, size: 18),
        backgroundColor: theme.colorScheme.primaryContainer,
        labelStyle: TextStyle(
          color: theme.colorScheme.onPrimaryContainer,
          fontSize: 12,
        ),
      ),
    );
  }

  String _getCategoryName(String categoryCode, List<MarketplaceCategory> categories) {
    try {
      final category = categories.firstWhere(
        (cat) => cat.code == categoryCode,
      );
      return category.name;
    } catch (e) {
      return categoryCode;
    }
  }

  String _getSortByLabel(String sortBy) {
    switch (sortBy) {
      case 'price_asc':
        return 'Giá: Thấp → Cao';
      case 'price_desc':
        return 'Giá: Cao → Thấp';
      case 'newest':
        return 'Mới nhất';
      case 'oldest':
        return 'Cũ nhất';
      default:
        return sortBy;
    }
  }
}

class _PostCard extends StatelessWidget {
  final MarketplacePost post;
  final String? currentResidentId;
  final List<MarketplaceCategory> categories;
  final VoidCallback onTap;

  const _PostCard({
    super.key,
    required this.post,
    this.currentResidentId,
    required this.categories,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHigh
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header - Người đăng bài
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        CupertinoIcons.person_fill,
                        color: theme.colorScheme.onPrimaryContainer,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.author?.name ?? 'Người dùng',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: (currentResidentId != null && 
                                      post.residentId == currentResidentId)
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (post.author?.unitNumber != null || post.author?.buildingName != null)
                            Row(
                              children: [
                                Icon(
                                  CupertinoIcons.home,
                                  size: 14,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                                const SizedBox(width: 4),
                                if (post.author?.buildingName != null) ...[
                                  Text(
                                    post.author!.buildingName!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (post.author?.unitNumber != null) ...[
                                    Text(
                                      ' - ',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                ],
                                if (post.author?.unitNumber != null)
                                  Text(
                                    post.author!.unitNumber!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatDate(post.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Title
                Text(
                  post.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (post.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    post.description,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                // Price, Category, Location
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (post.price != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.money_dollar,
                              size: 14,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              post.priceDisplay,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (post.category.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.square_grid_2x2,
                              size: 12,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getCategoryDisplayName(post),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (post.location != null && post.location!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.location,
                              size: 12,
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                post.location!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onTertiaryContainer,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                // Contact Info (if visible)
                if (post.contactInfo != null && 
                    ((post.contactInfo!.showPhone && post.contactInfo!.phone != null && post.contactInfo!.phone!.isNotEmpty) ||
                     (post.contactInfo!.showEmail && post.contactInfo!.email != null && post.contactInfo!.email!.isNotEmpty))) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.phone_circle,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      if (post.contactInfo!.showPhone && post.contactInfo!.phone != null && post.contactInfo!.phone!.isNotEmpty) ...[
                        Icon(
                          CupertinoIcons.phone,
                          size: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          post.contactInfo!.phone!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        if (post.contactInfo!.showEmail && post.contactInfo!.email != null && post.contactInfo!.email!.isNotEmpty)
                          const SizedBox(width: 12),
                      ],
                      if (post.contactInfo!.showEmail && post.contactInfo!.email != null && post.contactInfo!.email!.isNotEmpty) ...[
                        Icon(
                          CupertinoIcons.mail,
                          size: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            post.contactInfo!.email!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                // Images - Only show first 3 images, click to view all
                if (post.images.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: post.images.length > 3 ? 3 : post.images.length,
                      itemBuilder: (context, index) {
                        final image = post.images[index];
                        final isLastVisible = index == 2 && post.images.length > 3;
                        return GestureDetector(
                          onTap: () {
                            // Open image viewer
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ImageViewerScreen(
                                  images: post.images,
                                  initialIndex: index,
                                ),
                              ),
                            );
                          },
                          child: Stack(
                            children: [
                              Container(
                                width: 200,
                                margin: EdgeInsets.only(
                                  right: index < (post.images.length > 3 ? 2 : post.images.length - 1) ? 8 : 0,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Builder(
                                    builder: (context) {
                                      // Use thumbnail for lazy loading, fallback to full image
                                      final imageUrl = (image.thumbnailUrl != null && image.thumbnailUrl!.isNotEmpty)
                                          ? image.thumbnailUrl!
                                          : image.imageUrl;
                                      
                                      if (imageUrl.isNotEmpty) {
                                        return CachedNetworkImage(
                                          imageUrl: imageUrl,
                                          fit: BoxFit.cover,
                                          httpHeaders: {
                                            'ngrok-skip-browser-warning': 'true',
                                          },
                                          placeholder: (context, url) => Container(
                                            color: theme.colorScheme.surfaceContainerHighest,
                                            child: Center(
                                              child: SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: theme.colorScheme.primary,
                                                ),
                                              ),
                                            ),
                                          ),
                                          errorWidget: (context, url, error) => Container(
                                            color: theme.colorScheme.surfaceContainerHighest,
                                            child: Icon(
                                              CupertinoIcons.photo,
                                              size: 48,
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                                            ),
                                          ),
                                        );
                                      } else {
                                        return Container(
                                          color: theme.colorScheme.surfaceContainerHighest,
                                          child: Icon(
                                            CupertinoIcons.photo,
                                            size: 48,
                                            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ),
                              // Show "+X more" badge on last visible image if there are more images
                              if (isLastVisible)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: Colors.black.withValues(alpha: 0.5),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '+${post.images.length - 3}',
                                        style: theme.textTheme.titleLarge?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // Actions
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.chat_bubble,
                      size: 20,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${post.commentCount}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Vừa xong';
        }
        return '${difference.inMinutes} phút trước';
      }
      return '${difference.inHours} giờ trước';
    } else if (difference.inDays == 1) {
      return 'Hôm qua';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _getCategoryDisplayName(MarketplacePost post) {
    // Backend có thể trả về categoryName = category code, nên luôn map từ danh sách categories
    if (post.category.isNotEmpty) {
      try {
        final category = categories.firstWhere(
          (cat) => cat.code == post.category,
        );
        // Luôn dùng name (tiếng Việt) từ danh sách categories
        return category.name;
      } catch (e) {
        // Nếu không tìm thấy category, kiểm tra categoryName
        if (post.categoryName.isNotEmpty && post.categoryName != post.category) {
          return post.categoryName;
        }
        // Fallback về code
        return post.category;
      }
    }
    
    return '';
  }
}

