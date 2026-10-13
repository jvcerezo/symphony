import {
  ActionRowBuilder,
  ButtonBuilder,
  ButtonStyle,
  EmbedBuilder,
  MessageFlags,
  PermissionFlagsBits,
} from 'discord.js';
import { songsFor } from './sources.js';

const COLOR = 0x8b5cf6;
const QUEUE_PAGE = 10;

/** Commands start with this, so they don't clash with other bots' /play. */
export const PREFIX = 's!';

const ALIASES = {
  p: 'play', pn: 'playnext', s: 'skip', q: 'queue', np: 'nowplaying',
  rm: 'remove', leave: 'stop', dc: 'stop', h: 'help', commands: 'help',
};

const CONTROLS = ['skip', 'pause', 'resume', 'stop', 'queue', 'nowplaying', 'shuffle', 'remove', 'loop'];

const HELP = [
  ['play <song or link>', 'Play a song, a YouTube link, or a Spotify/YouTube playlist'],
  ['playnext <song or link>', 'Play it right after the current song'],
  ['skip', 'Skip to the next song'],
  ['pause / resume', 'Pause or carry on'],
  ['stop', 'Clear the queue and leave'],
  ['queue [page]', "What's coming up"],
  ['np', "What's playing"],
  ['shuffle', 'Shuffle the songs still to come'],
  ['remove <number>', 'Take a song out of the queue'],
  ['loop off / song / queue', 'Repeat the song or the whole queue'],
];

/**
 * `{ name, args }` for a message like "s!play daft punk", else null.
 * The prefix and command name ignore case.
 */
export function parseCommand(content) {
  const text = content.trim();
  if (!text.toLowerCase().startsWith(PREFIX)) return null;
  const [word = '', ...rest] = text.slice(PREFIX.length).trim().split(/\s+/);
  if (!word) return null;
  const name = word.toLowerCase();
  return { name: ALIASES[name] ?? name, args: rest.join(' ') };
}

/** Handles s! commands and the buttons on "Now playing" messages. */
export function createHandlers({ players, ytdlp }) {
  async function onMessage(message) {
    const command = parseCommand(message.content);
    if (!command) return;
    const player = players.get(message.guild);
    const send = (payload) => answer(message, payload);
    const { name, args } = command;

    if (name === 'help') return send({ embeds: [helpEmbed()] });
    if (name === 'play' || name === 'playnext') return play(message, player, args, { next: name === 'playnext' });
    if (!CONTROLS.includes(name)) return send(`I don't know \`${PREFIX}${name}\`. Try \`${PREFIX}help\`.`);

    const problem = controlProblem(message.member, player);
    if (problem) return send(problem);

    switch (name) {
      case 'skip': {
        const title = player.queue.current?.title ?? 'the song';
        return send(player.skip() ? `Skipped **${title}**.` : 'Nothing is playing.');
      }
      case 'pause':
        return send(player.pause() ? 'Paused.' : 'Nothing is playing.');
      case 'resume':
        return send(player.resume() ? 'Playing again.' : 'Nothing is paused.');
      case 'stop':
        player.stop();
        return send('Stopped and left the channel.');
      case 'queue':
        return send({ embeds: [queueEmbed(player, Number.parseInt(args, 10) || 1)] });
      case 'nowplaying': {
        const song = player.queue.current;
        return send(song ? { embeds: [nowPlayingEmbed(song, player)] } : 'Nothing is playing.');
      }
      case 'shuffle': {
        const n = player.queue.shuffle();
        return send(n > 1 ? `Shuffled ${n} songs.` : 'Not enough songs to shuffle.');
      }
      case 'remove': {
        const removed = player.queue.remove(Number.parseInt(args, 10));
        return send(removed ? `Removed **${removed.title}**.` : `There is no song at that number. See \`${PREFIX}queue\`.`);
      }
      case 'loop': {
        const mode = { off: 'off', song: 'song', one: 'song', queue: 'queue', all: 'queue' }[args.toLowerCase()];
        if (!mode) return send(`Use \`${PREFIX}loop off\`, \`${PREFIX}loop song\` or \`${PREFIX}loop queue\`.`);
        player.queue.loop = mode;
        return send({ off: 'Repeat is off.', song: 'Repeating this song.', queue: 'Repeating the queue.' }[mode]);
      }
    }
  }

  async function play(message, player, query, { next }) {
    const send = (payload) => answer(message, payload);
    if (!query) return send(`What should I play? For example: \`${PREFIX}play daft punk get lucky\``);
    const voice = message.member.voice.channel;
    if (!voice) return send('Join a voice channel first.');
    if (player.channelId && player.channelId !== voice.id && player.isPlaying) {
      return send(`I'm playing in <#${player.channelId}>. Join it to add songs.`);
    }
    const perms = voice.permissionsFor(message.guild.members.me);
    if (!perms?.has(PermissionFlagsBits.Connect) || !perms.has(PermissionFlagsBits.Speak)) {
      return send(`I'm not allowed to connect and speak in <#${voice.id}>.`);
    }

    message.channel.sendTyping().catch(() => {});
    try {
      const found = await songsFor(query, { ytdlp, requestedBy: message.author.id });
      await player.join(voice);
      player.textChannelId = message.channelId;
      const added = player.add(found.songs, { next });
      if (added === 0) return send('The queue is full.');
      if (found.isList) {
        const cut = added < found.songs.length ? ` (the queue is full, so ${found.songs.length - added} were left out)` : '';
        return send(`Added **${added}** songs from **${found.title}**${cut}.`);
      }
      const song = found.songs[0];
      return send(`${next ? 'Playing next' : 'Added'}: **${song.title}**${song.artist ? ` by ${song.artist}` : ''} (${time(song.durationSec)})`);
    } catch (e) {
      return send(`Could not play that: ${e.message}`);
    }
  }

  async function onButton(interaction) {
    const player = players.get(interaction.guild);
    const problem = controlProblem(interaction.member, player);
    if (problem) return interaction.reply({ content: problem, flags: MessageFlags.Ephemeral });
    if (interaction.customId === 'np:toggle') {
      if (player.isPaused) player.resume();
      else player.pause();
      return interaction.update({ components: [controls(player)] });
    }
    if (interaction.customId === 'np:skip') {
      player.skip();
      return interaction.update({ components: [] });
    }
    if (interaction.customId === 'np:stop') {
      player.stop();
      return interaction.update({ components: [] });
    }
  }

  return { onMessage, onButton };
}

/** Why this person can't control the music right now, or null if they can. */
function controlProblem(member, player) {
  if (!player.channelId) return `Nothing is playing. Start something with \`${PREFIX}play\`.`;
  if (member.voice.channelId !== player.channelId) return `Join <#${player.channelId}> to control the music.`;
  return null;
}

/**
 * Replies to the command message; posts in the channel instead when the bot
 * can't reply there (replying needs Read Message History).
 */
async function answer(message, payload) {
  const body = typeof payload === 'string' ? { content: payload } : payload;
  try {
    return await message.reply({ ...body, allowedMentions: { repliedUser: false } });
  } catch {
    return message.channel.send(body).catch(() => null);
  }
}

export function helpEmbed() {
  return new EmbedBuilder()
    .setColor(COLOR)
    .setTitle('Symphony commands')
    .setDescription(HELP.map(([cmd, what]) => `\`${PREFIX}${cmd}\` · ${what}`).join('\n'))
    .setFooter({ text: `Short forms: ${PREFIX}p, ${PREFIX}s, ${PREFIX}q, ${PREFIX}np` });
}

export function nowPlayingEmbed(song, player) {
  const embed = new EmbedBuilder()
    .setColor(COLOR)
    .setAuthor({ name: 'Now playing' })
    .setTitle(song.title)
    .setURL(song.url)
    .setDescription([
      song.artist,
      player ? `${time(player.positionSec)} / ${time(song.durationSec)}` : time(song.durationSec),
      song.requestedBy ? `Asked for by <@${song.requestedBy}>` : null,
    ].filter(Boolean).join('\n'));
  const id = song.url?.match(/v=([\w-]{11})/)?.[1];
  if (id) embed.setThumbnail(`https://i.ytimg.com/vi/${id}/hqdefault.jpg`);
  const next = player?.queue.upcoming[0];
  if (next) embed.setFooter({ text: `Up next: ${next.title}` });
  return embed;
}

export function controls(player) {
  return new ActionRowBuilder().addComponents(
    new ButtonBuilder().setCustomId('np:toggle').setStyle(ButtonStyle.Secondary).setLabel(player.isPaused ? 'Resume' : 'Pause'),
    new ButtonBuilder().setCustomId('np:skip').setStyle(ButtonStyle.Secondary).setLabel('Skip'),
    new ButtonBuilder().setCustomId('np:stop').setStyle(ButtonStyle.Danger).setLabel('Stop'),
  );
}

export function queueEmbed(player, page) {
  const { current, upcoming, loop } = player.queue;
  const pages = Math.max(1, Math.ceil(upcoming.length / QUEUE_PAGE));
  const p = Math.min(page, pages);
  const lines = upcoming
    .slice((p - 1) * QUEUE_PAGE, p * QUEUE_PAGE)
    .map((s, i) => `\`${(p - 1) * QUEUE_PAGE + i + 1}.\` ${s.title}${s.artist ? ` · ${s.artist}` : ''}`);
  const total = upcoming.reduce((sum, s) => sum + (s.durationSec ?? 0), 0);
  return new EmbedBuilder()
    .setColor(COLOR)
    .setTitle('Queue')
    .setDescription([
      current ? `**Now:** ${current.title}${current.artist ? ` · ${current.artist}` : ''}` : '**Now:** nothing',
      '',
      lines.length ? lines.join('\n') : 'Nothing else queued.',
    ].join('\n'))
    .setFooter({
      text: `${upcoming.length} songs · ${time(total)}${loop !== 'off' ? ` · repeating ${loop === 'song' ? 'this song' : 'the queue'}` : ''} · page ${p}/${pages}`,
    });
}

/** 3:45, or 1:02:03 for long ones. */
export function time(sec) {
  if (!Number.isFinite(sec)) return '?:??';
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = String(Math.floor(sec % 60)).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${s}` : `${m}:${s}`;
}
