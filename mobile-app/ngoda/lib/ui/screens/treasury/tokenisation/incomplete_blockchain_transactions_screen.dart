import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/common/report_pagination.dart';
import 'package:ngoda/data_models/operations/blockchain/incomplete_blockchain_transaction.dart';
import 'package:ngoda/data_models/params/blockchain_transaction_params.dart';
import 'package:ngoda/services/date_format_service.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/transaction_formatter.dart';
import 'package:ngoda/ui/screens/treasury/provider/incomplete_blockchain_trx_provider.dart';
import 'package:ngoda/ui/screens/treasury/provider/treasury_dashboard_provider.dart';
import 'package:ngoda/ui/screens/treasury/provider/treasury_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';
import 'package:webview_flutter/webview_flutter.dart';

class IncompleteBlockchainTransactionsScreen extends ConsumerStatefulWidget {
  const IncompleteBlockchainTransactionsScreen({super.key});

  @override
  ConsumerState<IncompleteBlockchainTransactionsScreen> createState() =>
      _IncompleteBlockchainTransactionsScreenState();
}

class _IncompleteBlockchainTransactionsScreenState
    extends ConsumerState<IncompleteBlockchainTransactionsScreen> {
  late BlockchainTransactionParams _params;

  String? _processingTransactionId;

  @override
  void initState() {
    super.initState();

    _params = const BlockchainTransactionParams(page: 1, pageSize: 50);
  }

  Future<void> _refresh() async {
    ref.invalidate(incompleteBlockainTrxProvider(_params));

    ref.invalidate(treasuryDashboardProvider);

    await ref.read(incompleteBlockainTrxProvider(_params).future);
  }

  void _previousPage() {
    if (_params.page <= 1 || _processingTransactionId != null) {
      return;
    }

    setState(() {
      _params = _params.copyWith(page: _params.page - 1);
    });
  }

  void _nextPage() {
    if (_processingTransactionId != null) {
      return;
    }

    setState(() {
      _params = _params.copyWith(page: _params.page + 1);
    });
  }

  void _changePageSize(int newPageSize) {
    if (_params.pageSize == newPageSize || _processingTransactionId != null) {
      return;
    }

    setState(() {
      _params = _params.copyWith(page: 1, pageSize: newPageSize);
    });
  }

  void _close() {
    ref.invalidate(incompleteBlockainTrxProvider(_params));

    ref.invalidate(treasuryDashboardProvider);

    context.pop();
  }

  Future<void> _openBlockExplorer(BlockchainTransaction transaction) async {
    final explorerUrl = transaction.explorerUrl!.trim();

    if (explorerUrl.isEmpty) {
      await DialogService.error(
        context,
        message: 'Block explorer URL is not available',
      );

      return;
    }

    final uri = Uri.tryParse(explorerUrl);

    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      await DialogService.error(context, message: 'Invalid block explorer URL');

      return;
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return BlockExplorerWebViewScreen(
            title: _shortenHash(transaction.transactionHash),
            explorerUrl: explorerUrl,
          );
        },
      ),
    );
  }

  Future<void> _processTransaction(BlockchainTransaction transaction) async {
    if (_processingTransactionId != null) {
      return;
    }

    final confirmed = await DialogService.confirm(
      context,
      title: 'Process Transaction',
      message:
          'Complete the pending blockchain transaction '
          '${_shortenHash(transaction.transactionHash)}?',
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _processingTransactionId = transaction.id;
    });

    try {
      final notifier = ref.read(treasuryTransactionProvider.notifier);

      await notifier.processIncompleteBlockchainTransaction(id: transaction.id);

      if (!mounted) {
        return;
      }

      DialogService.success(
        context,
        message: 'Blockchain transaction processed successfully',
      );

      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _processingTransactionId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(incompleteBlockainTrxProvider(_params));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Incomplete Blockchain Transactions',
              onClose: _close,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: transactionsAsync.when(
                  loading: () => const AppLoader(
                    message: 'Loading blockchain transactions',
                    fullScreen: false,
                  ),
                  error: (error, _) {
                    return _RefreshableState(
                      child: AppErrorState(message: error.toString()),
                    );
                  },
                  data: (response) {
                    if (response.error != null) {
                      return _RefreshableState(
                        child: AppErrorState(
                          message: response.error.toString(),
                        ),
                      );
                    }

                    final result = response.result;

                    if (result == null) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _TransactionsContent(
                      result: result,
                      pageSize: _params.pageSize,
                      processingTransactionId: _processingTransactionId,
                      processingDisabled: _processingTransactionId != null,
                      onPrevious:
                          result.pagination.hasPrevious &&
                              _processingTransactionId == null
                          ? _previousPage
                          : null,
                      onNext:
                          result.pagination.hasNext &&
                              _processingTransactionId == null
                          ? _nextPage
                          : null,
                      onPageSizeChanged: _changePageSize,
                      onOpenExplorer: _openBlockExplorer,
                      onProcessTransaction: _processTransaction,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionsContent extends StatelessWidget {
  const _TransactionsContent({
    required this.result,
    required this.pageSize,
    required this.processingTransactionId,
    required this.processingDisabled,
    required this.onPrevious,
    required this.onNext,
    required this.onPageSizeChanged,
    required this.onOpenExplorer,
    required this.onProcessTransaction,
  });

  final IncompleteBlockchainTransactions result;

  final int pageSize;
  final String? processingTransactionId;
  final bool processingDisabled;

  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  final ValueChanged<int> onPageSizeChanged;

  final Future<void> Function(BlockchainTransaction transaction) onOpenExplorer;

  final Future<void> Function(BlockchainTransaction transaction)
  onProcessTransaction;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Column(
      children: [
        Expanded(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(spacing.lg, 0, spacing.lg, spacing.lg),
            children: [
              _SummaryCard(totalEntries: result.pagination.totalEntries),
              SizedBox(height: spacing.xl),
              _SectionHeader(
                title: 'Transactions',
                trailing: result.pagination.totalEntries.toString(),
              ),
              SizedBox(height: spacing.sm),
              if (result.transactions.isEmpty)
                const AppEmptyState()
              else
                ...result.transactions.map((transaction) {
                  final isProcessing =
                      processingTransactionId == transaction.id;

                  return Padding(
                    padding: EdgeInsets.only(bottom: spacing.sm),
                    child: _BlockchainTransactionCard(
                      transaction: transaction,
                      isProcessing: isProcessing,
                      processingDisabled: processingDisabled,
                      onOpenExplorer: () {
                        onOpenExplorer(transaction);
                      },
                      onProcess: () {
                        onProcessTransaction(transaction);
                      },
                    ),
                  );
                }),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              spacing.sm,
              spacing.lg,
              spacing.sm,
            ),
            child: _PaginationControls(
              pagination: result.pagination,
              pageSize: pageSize,
              enabled: !processingDisabled,
              onPrevious: onPrevious,
              onNext: onNext,
              onPageSizeChanged: onPageSizeChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.totalEntries});

  final int totalEntries;

  static const Color gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(spacing.sm),
            decoration: BoxDecoration(
              color: gold.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.link_rounded, color: gold, size: iconSize.small),
          ),
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pending Reconciliation',
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: spacing.xs),
                Text(
                  'Blockchain transactions without documents',
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(
            totalEntries.toString(),
            style: AppTextStyles.smallNumber(
              context,
            ).copyWith(color: gold, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.sm,
            vertical: spacing.xs,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(radius.borderRadius),
          ),
          child: Text(
            trailing,
            style: AppTextStyles.tinyNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _BlockchainTransactionCard extends StatelessWidget {
  const _BlockchainTransactionCard({
    required this.transaction,
    required this.isProcessing,
    required this.processingDisabled,
    required this.onOpenExplorer,
    required this.onProcess,
  });

  final BlockchainTransaction transaction;
  final bool isProcessing;
  final bool processingDisabled;
  final VoidCallback onOpenExplorer;
  final VoidCallback onProcess;

  static const Color gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final borderRadius = BorderRadius.circular(radius.borderRadius);

    final hasExplorer = transaction.explorerUrl!.isNotEmpty;

    return Material(
      color: colorScheme.surface,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: hasExplorer ? onOpenExplorer : null,
        borderRadius: borderRadius,
        child: Padding(
          padding: EdgeInsets.all(spacing.lg),
          child: Column(
            children: [
              Row(
                children: [
                  _TransactionIcon(status: transaction.status),
                  SizedBox(width: spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatTxType(transaction.transactionType),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.small(
                            context,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: spacing.xs),
                        Text(
                          transaction.chain.toUpperCase(),
                          style: AppTextStyles.tiny(
                            context,
                          ).copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        NumberFormatService.formatAmount(
                          transaction.grossAmount,
                          currency: transaction.currencyCode,
                        ),
                        style: AppTextStyles.smallNumber(
                          context,
                        ).copyWith(color: gold, fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        DateFormatService.formatDisplayDate(
                          transaction.createdAt,
                        ),
                        style: AppTextStyles.tiny(
                          context,
                        ).copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: spacing.md),
              Divider(height: 1, color: colorScheme.outlineVariant),
              SizedBox(height: spacing.sm),
              _DetailRow(
                label: 'Quantity',
                value: transaction.quantity.toStringAsFixed(6),
                isText: false,
              ),
              SizedBox(height: spacing.sm),
              _DetailRow(
                label: 'Fiscal Period',
                value:
                    'FY ${transaction.fiscalYear} • '
                    'Period ${transaction.period}',
              ),
              SizedBox(height: spacing.sm),
              _DetailRow(
                label: 'Status',
                value: transaction.status.toUpperCase(),
                valueColor: _statusColor(transaction.status, colorScheme),
              ),
              SizedBox(height: spacing.sm),
              _DetailRow(
                label: 'Transaction Hash',
                value: _shortenHash(transaction.transactionHash),
                valueColor: hasExplorer ? gold : null,
                trailingIcon: hasExplorer ? Icons.open_in_new_rounded : null,
              ),
              SizedBox(height: spacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: processingDisabled ? null : onProcess,
                  icon: isProcessing
                      ? SizedBox(
                          width: context.iconSize.small,
                          height: context.iconSize.small,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.task_alt_rounded),
                  label: Text(
                    isProcessing
                        ? 'Processing Transaction'
                        : 'Process Transaction',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status, ColorScheme colorScheme) {
    switch (status.toLowerCase()) {
      case 'confirmed':
      case 'completed':
      case 'success':
        return Colors.green;

      case 'failed':
      case 'reverted':
        return colorScheme.error;

      default:
        return Colors.orange;
    }
  }
}

class _TransactionIcon extends StatelessWidget {
  const _TransactionIcon({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;

    switch (status.toLowerCase()) {
      case 'confirmed':
      case 'completed':
      case 'success':
        color = Colors.green;
        icon = Icons.check_rounded;
        break;

      case 'failed':
      case 'reverted':
        color = context.colorScheme.error;
        icon = Icons.close_rounded;
        break;

      default:
        color = Colors.orange;
        icon = Icons.schedule_rounded;
    }

    return Container(
      padding: EdgeInsets.all(context.spacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: context.iconSize.small),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.trailingIcon,
    this.isText = true,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final IconData? trailingIcon;
  final bool isText;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.tiny(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(width: spacing.sm),
        Flexible(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style:
                      (isText
                              ? AppTextStyles.tiny(context)
                              : AppTextStyles.tinyNumber(context))
                          .copyWith(
                            color: valueColor,
                            fontWeight: FontWeight.w700,
                          ),
                ),
              ),
              if (trailingIcon != null) ...[
                SizedBox(width: spacing.xs),
                Icon(
                  trailingIcon,
                  color: valueColor,
                  size: context.iconSize.small,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PaginationControls extends StatelessWidget {
  const _PaginationControls({
    required this.pagination,
    required this.pageSize,
    required this.enabled,
    required this.onPrevious,
    required this.onNext,
    required this.onPageSizeChanged,
  });

  final ReportPagination pagination;
  final int pageSize;
  final bool enabled;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<int> onPageSizeChanged;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final firstEntry = pagination.totalEntries == 0
        ? 0
        : ((pagination.page - 1) * pagination.pageSize) + 1;

    final calculatedLast = pagination.page * pagination.pageSize;

    final lastEntry = calculatedLast > pagination.totalEntries
        ? pagination.totalEntries
        : calculatedLast;

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                pagination.totalEntries == 0
                    ? 'No transactions'
                    : '$firstEntry - $lastEntry of '
                          '${pagination.totalEntries}',
                style: AppTextStyles.tiny(context).copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: pageSize,
                  isDense: true,
                  items: const [
                    DropdownMenuItem(value: 25, child: Text('25')),
                    DropdownMenuItem(value: 50, child: Text('50')),
                    DropdownMenuItem(value: 100, child: Text('100')),
                  ],
                  onChanged: enabled
                      ? (value) {
                          if (value != null) {
                            onPageSizeChanged(value);
                          }
                        }
                      : null,
                ),
              ),
              SizedBox(width: spacing.xs),
              Text(
                'per page',
                style: AppTextStyles.tiny(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled ? onPrevious : null,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Previous'),
                ),
              ),
              SizedBox(width: spacing.sm),
              Text(
                '${pagination.page} of '
                '${pagination.totalPages}',
                style: AppTextStyles.small(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled ? onNext : null,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Next'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RefreshableState extends StatelessWidget {
  const _RefreshableState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: Center(child: child),
        ),
      ],
    );
  }
}

class BlockExplorerWebViewScreen extends StatefulWidget {
  const BlockExplorerWebViewScreen({
    super.key,
    required this.title,
    required this.explorerUrl,
  });

  final String title;
  final String explorerUrl;

  @override
  State<BlockExplorerWebViewScreen> createState() =>
      _BlockExplorerWebViewScreenState();
}

class _BlockExplorerWebViewScreenState
    extends State<BlockExplorerWebViewScreen> {
  late final WebViewController _controller;

  int _loadingProgress = 0;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) {
              return;
            }

            setState(() {
              _loadingProgress = progress;
            });
          },
          onPageStarted: (_) {
            if (!mounted) {
              return;
            }

            setState(() {
              _hasError = false;
              _errorMessage = null;
              _loadingProgress = 0;
            });
          },
          onPageFinished: (_) {
            if (!mounted) {
              return;
            }

            setState(() {
              _loadingProgress = 100;
            });
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame != true) {
              return;
            }

            setState(() {
              _hasError = true;
              _errorMessage = error.description;
            });
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);

            if (uri == null) {
              return NavigationDecision.prevent;
            }

            if (uri.scheme == 'https' || uri.scheme == 'http') {
              return NavigationDecision.navigate;
            }

            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.explorerUrl));
  }

  Future<void> _reload() async {
    setState(() {
      _hasError = false;
      _errorMessage = null;
      _loadingProgress = 0;
    });

    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: widget.title,
              onClose: () {
                Navigator.of(context).pop();
              },
            ),
            if (_loadingProgress < 100 && !_hasError)
              LinearProgressIndicator(value: _loadingProgress / 100),
            Expanded(
              child: _hasError
                  ? _WebViewErrorState(
                      message: _errorMessage ?? 'Unable to load block explorer',
                      onRetry: _reload,
                    )
                  : WebViewWidget(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebViewErrorState extends StatelessWidget {
  const _WebViewErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language_rounded,
              size: context.iconSize.small,
              color: colorScheme.onSurfaceVariant,
            ),
            SizedBox(height: spacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.small(context),
            ),
            SizedBox(height: spacing.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortenHash(String hash) {
  final value = hash.trim();

  if (value.length <= 13) {
    return value;
  }

  return '${value.substring(0, 8)}...'
      '${value.substring(value.length - 4)}';
}
