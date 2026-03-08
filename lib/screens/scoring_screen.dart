import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';
import 'scoreboard_screen.dart';
import 'analysis_screen.dart';

class ScoringScreen extends StatefulWidget {
  final String matchId;
  const ScoringScreen({super.key, required this.matchId});
  @override
  State<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends State<ScoringScreen> {
  bool _initDialogShown = false;
  bool _inningsTransitionShown = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (ctx, provider, _) {
      final match = provider.matches.firstWhere((m) => m.id == widget.matchId);
      provider.setActiveMatch(match);

      if (match.status == MatchStatus.completed) {
        return _MatchCompletedScreen(match: match, provider: provider);
      }

      final innings = match.currentInnings;

      if (innings != null &&
          match.firstInnings != null &&
          match.firstInnings!.isCompleted &&
          match.secondInnings != null &&
          innings.strikerBatsmanId == null &&
          !_inningsTransitionShown) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _inningsTransitionShown = true;
          _showInningsBreakDialog(context, provider, match, innings);
        });
      }

      if (innings != null &&
          innings.strikerBatsmanId == null &&
          !_initDialogShown &&
          !(match.firstInnings != null &&
              match.firstInnings!.isCompleted &&
              match.secondInnings != null)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _initDialogShown = true;
          _showInitDialog(context, provider, match, innings);
        });
      }

      if (innings == null) {
        return _MatchCompletedScreen(match: match, provider: provider);
      }

      return Scaffold(
        backgroundColor: AppTheme.surface,
        appBar: _buildAppBar(context, match, provider),
        body: SafeArea(
          child: Column(
            children: [
              // উপরের ইনফরমেশনগুলো স্ক্রল হবে যদি জায়গা কম থাকে
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _ScoreHeader(match: match, innings: innings, provider: provider),
                      _BatsmenInfo(match: match, innings: innings, provider: provider),
                      _BowlerInfo(match: match, innings: innings, provider: provider),
                      _ExtrasInfo(innings: innings),
                      _ThisOver(innings: innings),
                    ],
                  ),
                ),
              ),
              // রান দেওয়ার প্যাড সব সময় নিচে ফিক্সড থাকবে
              _ScoringPad(
                match: match,
                innings: innings,
                provider: provider,
                onWicket: () => _showWicketDialog(context, provider, match, innings),
                onOverEnd: () => _showChangeBowlerDialog(context, provider, match),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    });
  }

  AppBar _buildAppBar(
      BuildContext context, CricketMatch match, AppProvider provider) {
    final hostTeam = provider.getTeam(match.hostTeamId);
    final visitorTeam = provider.getTeam(match.visitorTeamId);
    return AppBar(
      title: Text(
        '${hostTeam?.name ?? ''} vs ${visitorTeam?.name ?? ''}',
        style: const TextStyle(fontSize: 15),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.undo),
          tooltip: 'Undo',
          onPressed: () => provider.undoLastBall(),
        ),
        IconButton(
          icon: const Icon(Icons.list_alt),
          tooltip: 'Scoreboard',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ScoreboardScreen(matchId: match.id)),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.bar_chart),
          tooltip: 'Analysis',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => AnalysisScreen(matchId: match.id)),
          ),
        ),
      ],
    );
  }

  void _showInitDialog(BuildContext context, AppProvider provider,
      CricketMatch match, Innings innings) {
    final teamPlayers =
    provider.getTeamPlayersForMatch(innings.teamId, match);
    final bowlingTeamId = innings.teamId == match.hostTeamId
        ? match.visitorTeamId
        : match.hostTeamId;
    final bowlerPlayers =
    provider.getTeamPlayersForMatch(bowlingTeamId, match);

    String? striker = teamPlayers.isNotEmpty ? teamPlayers[0].id : null;
    String? nonStriker = teamPlayers.length > 1 ? teamPlayers[1].id : null;
    String? bowler = bowlerPlayers.isNotEmpty ? bowlerPlayers[0].id : null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          title: Text('Start Innings',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _PlayerDropdown(
                label: 'Opening Batsman (Striker)',
                players: teamPlayers,
                value: striker,
                onChanged: (v) => setS(() => striker = v),
              ),
              const SizedBox(height: 12),
              _PlayerDropdown(
                label: 'Opening Batsman (Non-striker)',
                players: teamPlayers,
                value: nonStriker,
                onChanged: (v) => setS(() => nonStriker = v),
              ),
              const SizedBox(height: 12),
              _PlayerDropdown(
                label: 'Opening Bowler',
                players: bowlerPlayers,
                value: bowler,
                onChanged: (v) => setS(() => bowler = v),
              ),
            ]),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                if (striker != null &&
                    nonStriker != null &&
                    bowler != null &&
                    striker != nonStriker) {
                  provider.initInnings(
                    strikerBatsmanId: striker!,
                    nonStrikerBatsmanId: nonStriker!,
                    bowlerId: bowler!,
                  );
                  Navigator.pop(ctx2);
                } else {
                  ScaffoldMessenger.of(ctx2).showSnackBar(
                    const SnackBar(
                        content: Text('Please select different batsmen!')),
                  );
                }
              },
              child: const Text('Start'),
            ),
          ],
        ),
      ),
    );
  }

  void _showInningsBreakDialog(BuildContext context, AppProvider provider,
      CricketMatch match, Innings innings) {
    final firstInnings = match.firstInnings!;
    final battingTeam = provider.getTeam(innings.teamId);
    final target = firstInnings.totalRuns + 1;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text('Innings Break!',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.sports_cricket,
              size: 48, color: AppTheme.primary),
          const SizedBox(height: 12),
          Text(
            '${battingTeam?.name ?? "Team"} needs $target runs to win',
            style: GoogleFonts.poppins(fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'in ${match.totalOvers} overs',
            style: GoogleFonts.poppins(
                color: AppTheme.textSecondary, fontSize: 13),
          ),
        ]),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _initDialogShown = false;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showInitDialog(context, provider, match, innings);
              });
            },
            child: const Text('Start 2nd Innings'),
          ),
        ],
      ),
    );
  }

  void _showWicketDialog(BuildContext context, AppProvider provider,
      CricketMatch match, Innings innings) {
    final battingTeamPlayers =
    provider.getTeamPlayersForMatch(innings.teamId, match);
    final available = battingTeamPlayers
        .where((p) =>
    !p.isOut &&
        p.id != innings.strikerBatsmanId &&
        p.id != innings.nonStrikerBatsmanId)
        .toList();

    if (available.isEmpty) return;
    String? nextBatsman = available[0].id;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          title: Text('Wicket! — Next Batsman',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold, color: Colors.red)),
          content: _PlayerDropdown(
            label: 'Next Batsman',
            players: available,
            value: nextBatsman,
            onChanged: (v) => setS(() => nextBatsman = v),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                if (nextBatsman != null) {
                  provider.setNextBatsman(nextBatsman!);
                  Navigator.pop(ctx2);
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangeBowlerDialog(
      BuildContext context, AppProvider provider, CricketMatch match) {
    final innings = match.currentInnings;
    if (innings == null) return;

    final bowlingTeamId = innings.teamId == match.hostTeamId
        ? match.visitorTeamId
        : match.hostTeamId;
    final bowlers =
    provider.getTeamPlayersForMatch(bowlingTeamId, match);
    final available =
    bowlers.where((p) => p.id != innings.currentBowlerId).toList();

    if (available.isEmpty) return;
    String? newBowler = available[0].id;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          title: Text('End of Over — New Bowler',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: _PlayerDropdown(
            label: 'Select Bowler',
            players: available,
            value: newBowler,
            onChanged: (v) => setS(() => newBowler = v),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                if (newBowler != null) {
                  provider.setNewBowler(newBowler!);
                  Navigator.pop(ctx2);
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreHeader extends StatelessWidget {
  final CricketMatch match;
  final Innings innings;
  final AppProvider provider;

  const _ScoreHeader(
      {required this.match,
        required this.innings,
        required this.provider});

  @override
  Widget build(BuildContext context) {
    final battingTeam = provider.getTeam(innings.teamId);
    final isSecondInnings = match.firstInnings != null &&
        match.firstInnings!.isCompleted &&
        match.secondInnings?.teamId == innings.teamId;

    Widget? targetBar;
    if (isSecondInnings && match.firstInnings != null) {
      final target = match.firstInnings!.totalRuns + 1;
      final needed = target - innings.totalRuns;
      final ballsLeft = (match.totalOvers * 6) - innings.totalBalls;
      final prob = provider.getWinProbability(match);

      targetBar = Container(
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: AppTheme.primaryDark,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Target: $target',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13)),
            Text(
              needed > 0
                  ? 'Need $needed off $ballsLeft balls'
                  : 'Won!',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            Text(
              '% ${(prob * 100).round()}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return Container(
      color: AppTheme.primary,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(battingTeam?.name ?? 'Batting',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                    Text(
                      '${innings.totalRuns} - ${innings.wickets}',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.bold),
                    ),
                  ]),
              const Spacer(),
              Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                        'CRR: ${innings.runRate.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _showEditOversDialog(context, provider, match),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${innings.completedOvers}.${innings.ballsInCurrentOver} / ${match.totalOvers} ov',
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.add_circle_outline, size: 16, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ]),
            ],
          ),
        ),
        if (targetBar != null) targetBar,
      ]),
    );
  }

  void _showEditOversDialog(BuildContext context, AppProvider provider, CricketMatch match) {
    final controller = TextEditingController(text: match.totalOvers.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change Total Overs', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'New Overs Limit',
            hintText: 'Enter number of overs',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(controller.text);
              if (val != null && val > 0) {
                provider.updateMatchOvers(val);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
}

class _BatsmenInfo extends StatelessWidget {
  final CricketMatch match;
  final Innings innings;
  final AppProvider provider;

  const _BatsmenInfo(
      {required this.match,
        required this.innings,
        required this.provider});

  @override
  Widget build(BuildContext context) {
    final striker = innings.strikerBatsmanId != null
        ? provider.getPlayerById(innings.strikerBatsmanId!, match)
        : null;
    final nonStriker = innings.nonStrikerBatsmanId != null
        ? provider.getPlayerById(innings.nonStrikerBatsmanId!, match)
        : null;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(children: [
          // Header row
          Row(children: [
            const Text('Batsmen',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => provider.swapBatsmen(),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.swap_vert,
                    size: 16, color: AppTheme.primary),
              ),
            ),
          ]),
          const Divider(height: 8),

          // Table — header + data rows perfectly aligned
          Table(
            columnWidths: const {
              0: FlexColumnWidth(),   // নামের column flexible
              1: FixedColumnWidth(36),
              2: FixedColumnWidth(36),
              3: FixedColumnWidth(36),
              4: FixedColumnWidth(36),
              5: FixedColumnWidth(44),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              // Header
              TableRow(
                decoration: const BoxDecoration(),
                children: [
                  for (final h in ['', 'R', 'B', '4s', '6s', 'SR'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(h,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textSecondary)),
                    ),
                ],
              ),
              // Striker row
              if (striker != null)
                _batsmanTableRow(context, striker, true),
              // Non-striker row
              if (nonStriker != null)
                _batsmanTableRow(context, nonStriker, false),
            ],
          ),

          if (striker == null && nonStriker == null)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Waiting for batsmen...',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
        ]),
      ),
    );
  }

  TableRow _batsmanTableRow(BuildContext context, Player p, bool isStriker) {
    return TableRow(children: [
      // নাম cell
      GestureDetector(
        onLongPress: () => _showEditNameDialog(context, p),
        onTap: () => _showChangeBatsmanDialog(context, p, isStriker),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            if (isStriker)
              const Icon(Icons.sports_cricket,
                  size: 13, color: AppTheme.primary),
            const SizedBox(width: 2),
            Flexible(
              child: Text(p.name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: GoogleFonts.poppins(
                      fontWeight: isStriker ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 13)),
            ),
            const Icon(Icons.keyboard_arrow_down,
                size: 13, color: AppTheme.textSecondary),
          ]),
        ),
      ),
      // Stats cells
      for (final val in [
        '${p.runs}',
        '${p.balls}',
        '${p.fours}',
        '${p.sixes}',
        p.strikeRate.toStringAsFixed(1),
      ])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(val,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: isStriker && val == '${p.runs}'
                      ? FontWeight.bold
                      : FontWeight.normal)),
        ),
    ]);
  }

  void _showChangeBatsmanDialog(BuildContext context, Player current, bool isStriker) {
    final battingTeamPlayers = provider.getTeamPlayersForMatch(innings.teamId, match);
    final available = battingTeamPlayers
        .where((p) =>
    !p.isOut &&
        p.id != innings.strikerBatsmanId &&
        p.id != innings.nonStrikerBatsmanId)
        .toList();
    if (available.isEmpty) return;
    String? selected = available[0].id;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          title: Text('Change Batsman',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: _PlayerDropdown(
            label: 'Select Batsman',
            players: available,
            value: selected,
            onChanged: (v) => setS(() => selected = v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx2),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (selected != null) {
                  if (isStriker) {
                    provider.setNextBatsman(selected!);
                  } else {
                    provider.setNonStriker(selected!);
                  }
                  Navigator.pop(ctx2);
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditNameDialog(BuildContext context, Player p) {
    final ctrl = TextEditingController(text: p.name);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Edit Name',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Player Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                provider.renameTempPlayer(p.id, ctrl.text.trim(), match);
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _batsmanRow(BuildContext context, Player p, bool isStriker) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      // নাম অংশ — fixed width বাদ দিয়ে বাকি সব জায়গা নেবে
      Expanded(
        child: GestureDetector(
          onLongPress: () => _showEditNameDialog(context, p),
          onTap: () => _showChangeBatsmanDialog(context, p, isStriker),
          child: Row(children: [
            if (isStriker)
              const Icon(Icons.sports_cricket,
                  size: 14, color: AppTheme.primary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(p.name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: GoogleFonts.poppins(
                      fontWeight: isStriker
                          ? FontWeight.w600
                          : FontWeight.w400,
                      fontSize: 13)),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_down,
                size: 14, color: AppTheme.textSecondary),
          ]),
        ),
      ),
      // Stats — সবসময় fixed width এ ডান দিকে
      for (final val in [
        '${p.runs}',
        '${p.balls}',
        '${p.fours}',
        '${p.sixes}',
        p.strikeRate.toStringAsFixed(1),
      ])
        SizedBox(
          width: 40,
          child: Text(val,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: isStriker && val == '${p.runs}'
                      ? FontWeight.bold
                      : FontWeight.normal)),
        ),
    ]),
  );
}

class _BowlerInfo extends StatelessWidget {
  final CricketMatch match;
  final Innings innings;
  final AppProvider provider;

  const _BowlerInfo(
      {required this.match,
        required this.innings,
        required this.provider});

  @override
  Widget build(BuildContext context) {
    final bowler = innings.currentBowlerId != null
        ? provider.getPlayerById(innings.currentBowlerId!, match)
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          const Icon(Icons.sports_baseball,
              size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onLongPress: () => _showEditBowlerName(context, bowler),
              onTap: () => _showChangeBowler(context, bowler),
              child: Row(children: [
                Flexible(child: Text(bowler?.name ?? 'Bowler',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down,
                    size: 16, color: AppTheme.textSecondary),
              ]),
            ),
          ),
          for (final kv in [
            ('O', bowler?.oversBowledDisplay ?? '0.0'),
            ('M', '${bowler?.maidens ?? 0}'),
            ('R', '${bowler?.runsConceded ?? 0}'),
            ('W', '${bowler?.wickets ?? 0}'),
            ('Eco', bowler?.bowlingEconomy.toStringAsFixed(2) ?? '0.00'),
          ])
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(children: [
                Text(kv.$1,
                    style: const TextStyle(
                        fontSize: 10, color: AppTheme.textSecondary)),
                Text(kv.$2,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            ),
        ]),
      ),
    );
  }

  void _showEditBowlerName(BuildContext context, Player? bowler) {
    if (bowler == null) return;
    final ctrl = TextEditingController(text: bowler.name);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Edit Bowler Name',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Bowler Name', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                provider.renameTempPlayer(bowler.id, ctrl.text.trim(), match);
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showChangeBowler(BuildContext context, Player? currentBowler) {
    final bowlingTeamId = innings.teamId == match.hostTeamId
        ? match.visitorTeamId
        : match.hostTeamId;
    final available = provider
        .getTeamPlayersForMatch(bowlingTeamId, match)
        .where((p) => p.id != innings.currentBowlerId)
        .toList();
    if (available.isEmpty) return;
    String? selected = available[0].id;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          title: Text('Change Bowler',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: _PlayerDropdown(
            label: 'Select Bowler',
            players: available,
            value: selected,
            onChanged: (v) => setS(() => selected = v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx2),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (selected != null) {
                  provider.setNewBowler(selected!);
                  Navigator.pop(ctx2);
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExtrasInfo extends StatelessWidget {
  final Innings innings;
  const _ExtrasInfo({required this.innings});

  Map<String, int> _calcExtras() {
    int wd = 0, nb = 0, b = 0, lb = 0;
    for (final e in innings.ballEvents) {
      switch (e.type) {
        case BallType.wide:
          wd += e.runs;
          break;
        case BallType.noBall:
          nb += e.runs + 1;
          break;
        case BallType.bye:
          b += e.runs;
          break;
        case BallType.legBye:
          lb += e.runs;
          break;
        default:
          break;
      }
    }
    return {'Wd': wd, 'Nb': nb, 'B': b, 'Lb': lb};
  }

  @override
  Widget build(BuildContext context) {
    final extras = _calcExtras();
    final total = extras.values.fold(0, (a, b) => a + b);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          const Icon(Icons.add_circle_outline, size: 15, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text('Extras',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('$total',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ),
          const Spacer(),
          ...extras.entries.map((e) => Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Column(children: [
              Text(e.key,
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.textSecondary)),
              Text('${e.value}',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
          )),
        ]),
      ),
    );
  }
}

class _ThisOver extends StatelessWidget {
  final Innings innings;

  const _ThisOver({required this.innings});

  List<BallEvent> _getCurrentOverBalls() {
    int legalCount = 0;
    int startIdx = 0;
    final targetLegal = innings.completedOvers * 6;

    for (int i = 0; i < innings.ballEvents.length; i++) {
      final b = innings.ballEvents[i];
      if (b.type != BallType.wide && b.type != BallType.noBall) {
        legalCount++;
      }
      if (legalCount == targetLegal) {
        startIdx = i + 1;
        break;
      }
    }

    if (targetLegal == 0 && legalCount == 0) {
      startIdx = 0;
    }

    return innings.ballEvents.sublist(startIdx);
  }

  @override
  Widget build(BuildContext context) {
    final thisOverBalls = _getCurrentOverBalls();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        const Text('This over: ',
            style: TextStyle(
                fontSize: 12, color: AppTheme.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: thisOverBalls.isEmpty
                  ? [
                const Text('—',
                    style: TextStyle(
                        color: AppTheme.textSecondary))
              ]
                  : thisOverBalls
                  .map((b) => _BallChip(ball: b))
                  .toList(),
            ),
          ),
        ),
      ]),
    );
  }
}

class _BallChip extends StatelessWidget {
  final BallEvent ball;

  const _BallChip({required this.ball});

  @override
  Widget build(BuildContext context) {
    Color bg;
    switch (ball.type) {
      case BallType.wicket:
        bg = Colors.red;
        break;
      case BallType.wide:
      case BallType.noBall:
        bg = Colors.orange;
        break;
      default:
        bg = ball.runs == 4
            ? Colors.blue
            : ball.runs == 6
            ? Colors.purple
            : AppTheme.primary;
    }
    return Container(
      margin: const EdgeInsets.only(right: 6),
      width: 32,
      height: 32,
      decoration:
      BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Center(
          child: Text(ball.display,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11))),
    );
  }
}

class _ScoringPad extends StatefulWidget {
  final CricketMatch match;
  final Innings innings;
  final AppProvider provider;
  final VoidCallback onWicket;
  final VoidCallback onOverEnd;

  const _ScoringPad({
    required this.match,
    required this.innings,
    required this.provider,
    required this.onWicket,
    required this.onOverEnd,
  });

  @override
  State<_ScoringPad> createState() => _ScoringPadState();
}

class _ScoringPadState extends State<_ScoringPad> {
  bool _wide = false;
  bool _noBall = false;
  bool _bye = false;
  bool _legBye = false;

  void _addBall(int runs, {bool isWicket = false, String? dismissalType, String? fielderId}) {
    if (widget.innings.strikerBatsmanId == null) return;

    BallType type;
    if (isWicket) {
      type = BallType.wicket;
    } else if (_wide) {
      type = BallType.wide;
    } else if (_noBall) {
      type = BallType.noBall;
    } else if (_bye) {
      type = BallType.bye;
    } else if (_legBye) {
      type = BallType.legBye;
    } else {
      type = BallType.normal;
    }

    final innings = widget.innings;
    final over =
        '${innings.completedOvers}.${innings.ballsInCurrentOver + 1}';

    final event = BallEvent(
      type: type,
      runs: runs,
      dismissalType: dismissalType,
      fielderId: fielderId,
      bowlerId: innings.currentBowlerId,
      batsmanId: innings.strikerBatsmanId,
      overNumber: over,
    );

    final prevLegalBalls = innings.totalBalls;
    widget.provider.addBall(event);

    setState(() {
      _wide = false;
      _noBall = false;
      _bye = false;
      _legBye = false;
    });

    if (isWicket) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onWicket();
      });
      return;
    }

    final isLegal =
        type != BallType.wide && type != BallType.noBall;
    if (isLegal) {
      final newLegalBalls = prevLegalBalls + 1;
      if (newLegalBalls % 6 == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onOverEnd();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(children: [
        Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ExtraChip('Wide', _wide, (v) => setState(() {
                _wide = v;
                if (v) {
                  _noBall = false;
                  _bye = false;
                  _legBye = false;
                }
              })),
              _ExtraChip('No Ball', _noBall, (v) => setState(() {
                _noBall = v;
                if (v) {
                  _wide = false;
                  _bye = false;
                  _legBye = false;
                }
              })),
              _ExtraChip('Bye', _bye, (v) => setState(() {
                _bye = v;
                if (v) {
                  _wide = false;
                  _noBall = false;
                  _legBye = false;
                }
              })),
              _ExtraChip('Leg Bye', _legBye, (v) => setState(() {
                _legBye = v;
                if (v) {
                  _wide = false;
                  _noBall = false;
                  _bye = false;
                }
              })),
            ]),
        const SizedBox(height: 12),
        Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final r in [0, 1, 2, 3, 4, 5, 6])
                _RunButton(
                  label: '$r',
                  color: r == 4
                      ? Colors.blue
                      : r == 6
                      ? Colors.purple
                      : AppTheme.primary,
                  onTap: () => _addBall(r),
                ),
            ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding:
                  const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(Icons.close),
              label: const Text('Wicket',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _showDismissalDialog(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.people,
                  color: AppTheme.primary),
              label: const Text("P'ship",
                  style: TextStyle(color: AppTheme.primary)),
              onPressed: () =>
                  _showPartnershipsSheet(context),
            ),
          ),
        ]),
      ]),
    );
  }

  void _showDismissalDialog() {
    final match = widget.match;
    final innings = widget.innings;
    final provider = widget.provider;

    final bowlingTeamId = innings.teamId == match.hostTeamId
        ? match.visitorTeamId
        : match.hostTeamId;
    final fieldingPlayers = provider.getTeamPlayersForMatch(bowlingTeamId, match);

    final types = ['Bowled', 'Caught', 'LBW', 'Run Out', 'Stumped', 'Hit Wicket', 'Retired'];
    String selected = types[0];
    String? catchFielderId;
    String? runOutFielderId;
    String? stumpedFielderId;

    // dismissal types যেগুলোতে fielder লাগে
    bool needsFielder(String t) => t == 'Caught' || t == 'Run Out' || t == 'Stumped';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setS) {
          String? currentFielderId = selected == 'Caught'
              ? catchFielderId
              : selected == 'Run Out'
              ? runOutFielderId
              : selected == 'Stumped'
              ? stumpedFielderId
              : null;

          return AlertDialog(
            title: Text('Dismissal Info',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold, color: Colors.red)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Dismissal type selection
                ...types.map((t) => RadioListTile<String>(
                  dense: true,
                  title: Text(t, style: const TextStyle(fontSize: 14)),
                  value: t,
                  groupValue: selected,
                  activeColor: Colors.red,
                  onChanged: (v) => setS(() => selected = v!),
                )),

                // Fielder dropdown (Caught / Run Out / Stumped)
                if (needsFielder(selected)) ...[
                  const Divider(),
                  Text(
                    selected == 'Caught'
                        ? 'Caught by'
                        : selected == 'Run Out'
                        ? 'Run out by'
                        : 'Stumped by',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTheme.primary),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Select Fielder',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    value: currentFielderId,
                    items: fieldingPlayers
                        .map((p) => DropdownMenuItem(
                        value: p.id, child: Text(p.name)))
                        .toList(),
                    onChanged: (v) => setS(() {
                      if (selected == 'Caught') catchFielderId = v;
                      if (selected == 'Run Out') runOutFielderId = v;
                      if (selected == 'Stumped') stumpedFielderId = v;
                    }),
                  ),
                ],
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx2),
                  child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  final fielderId = selected == 'Caught'
                      ? catchFielderId
                      : selected == 'Run Out'
                      ? runOutFielderId
                      : selected == 'Stumped'
                      ? stumpedFielderId
                      : null;

                  // fielder বাধ্যতামূলক
                  if (needsFielder(selected) && fielderId == null) {
                    ScaffoldMessenger.of(ctx2).showSnackBar(
                      SnackBar(
                        content: Text(
                          selected == 'Caught'
                              ? 'কে catch করেছে select করুন'
                              : selected == 'Run Out'
                              ? 'কে run out করেছে select করুন'
                              : 'কে stump করেছে select করুন',
                        ),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    return;
                  }

                  Navigator.pop(ctx2);
                  _addBall(0,
                      isWicket: true,
                      dismissalType: selected,
                      fielderId: fielderId);
                },
                child: const Text('Confirm Wicket'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPartnershipsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius:
          BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _PartnershipsSheet(
          match: widget.match,
          innings: widget.innings,
          provider: widget.provider),
    );
  }
}

class _PartnershipsSheet extends StatelessWidget {
  final CricketMatch match;
  final Innings innings;
  final AppProvider provider;

  const _PartnershipsSheet(
      {required this.match,
        required this.innings,
        required this.provider});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Partnerships',
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...innings.partnerships.map((p) {
            final b1 =
            provider.getPlayerById(p.batsman1Id, match);
            final b2 =
            provider.getPlayerById(p.batsman2Id, match);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                    child: Text(
                        '${b1?.name ?? '-'} & ${b2?.name ?? '-'}')),
                Text('${p.runs} (${p.balls}b)',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600)),
              ]),
            );
          }),
          if (innings.partnerships.isEmpty)
            const Text('No partnerships yet'),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _MatchCompletedScreen extends StatelessWidget {
  final CricketMatch match;
  final AppProvider provider;

  const _MatchCompletedScreen(
      {required this.match, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match Result')),
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.emoji_events, size: 80, color: Colors.amber),
          const SizedBox(height: 16),
          Text(match.resultDescription ?? 'Match Over',
              style: GoogleFonts.poppins(
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to Home'),
          ),
        ]),
      ),
    );
  }
}

class _PlayerDropdown extends StatelessWidget {
  final String label;
  final List<Player> players;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _PlayerDropdown({
    required this.label,
    required this.players,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      value: value,
      items: players
          .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

// ✅ এখানে বাটনগুলোর টেক্সট উজ্জ্বল ও মোটা করা হয়েছে
class _ExtraChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _ExtraChip(this.label, this.selected, this.onSelected);

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold, // লেখা মোটা করা হয়েছে
          color: selected ? Colors.white : Colors.black, // গাঢ় কালো টেক্সট
        ),
      ),
      selected: selected,
      onSelected: onSelected,
      selectedColor: AppTheme.primary, // সিলেক্ট করলে উজ্জ্বল নীল হবে
      checkmarkColor: Colors.white,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? AppTheme.primary : Colors.grey.shade400,
          width: 1.5,
        ),
      ),
    );
  }
}

class _RunButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _RunButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

