import {
  ActionRowBuilder,
  ButtonBuilder,
  ButtonStyle,
  EmbedBuilder,
  InteractionContextType,
  MessageFlags,
  PermissionFlagsBits,
  SlashCommandBuilder,
} from 'discord.js';
import { songsFor } from './sources.js';

const COLOR = 0x8b5cf6;
const QUEUE_PAGE = 10;

const guildOnly = (b) => b.setContexts(InteractionContextType.Guild);

export const commandData = [
  guildOnly(new SlashCommandBuilder().setName('play').setDescription('Play a song, a YouTube link, or a Spotify/YouTube playlist')
    .addStringOption((o) => o.setName('song').setDescription('Song name or link').setRequired(true))),
  guildOnly(new SlashCommandBuilder().setName('playnext').setDescription('Play this right after the current song')
    .addStringOption((o) => o.setName('song').setDescription('Song name or link').setRequired(true))),
  guildOnly(new SlashCommandBuilder().setName('skip').setDescription('Skip to the next song')),
  guildOnly(new SlashCommandBuilder().setName('pause').setDescription('Pause the music')),
  guildOnly(new SlashCommandBuilder().setName('resume').setDescription('Carry on playing')),
  guildOnly(new SlashCommandBuilder().setName('stop').setDescription('Stop, clear the queue and leave the channel')),
  guildOnly(new SlashCommandBuilder().setName('queue').setDescription("Show what's coming up")
    .addIntegerOption((o) => o.setName('page').setDescription('Page number').setMinValue(1))),
  guildOnly(new SlashCommandBuilder().setName('nowplaying').setDescription("Show what's playing")),
  guildOnly(new SlashCommandBuilder().setName('shuffle').setDescription('Shuffle the songs still to come')),
  guildOnly(new SlashCommandBuilder().setName('remove').setDescription('Remove a song from the queue')
    .addIntegerOption((o) => o.setName('position').setDescription('Its number in /queue').setRequired(true).setMinValue(1))),
  guildOnly(new SlashCommandBuilder().setName('loop').setDescription('Repeat the song or the whole queue')
    .addStringOption((o) => o.setName('mode').setDescription('What to repeat').setRequired(true)
      .addChoices({ name: 'Off', value: 'off' }, { name: 'This song', value: 'song' }, { name: 'The queue', value: 'queue' }))),
].map((b) => b.toJSON());

/** Handles slash commands and the buttons on "Now playing" messages. */
export function createHandlers({ players, ytdlp }) {
  async function onCommand(interaction) {
    const player = players.get(interaction.guild);
    const name = interaction.commandName;

    if (name === 'play' || name === 'playnext') return play(interaction, player, { next: name === 'playnext' });

    const problem = controlProblem(interaction, player);
    if (problem) return reply(interaction, problem);

    switch (name) {
      case 'skip': {
        const title = player.queue.current?.title ?? 'the song';
        return reply(interaction, player.skip() ? `Skipped **${title}**.` : 'Nothing is playing.', false);
      }
      case 'pause':
        return reply(interaction, player.pause() ? 'Paused.' : 'Nothing is playing.', false);
      case 'resume':
        return reply(interaction, player.resume() ? 'Playing again.' : 'Nothing is paused.', false);
      case 'stop':
        player.stop();
        return reply(interaction, 'Stopped and left the channel.', false);
      case 'queue':
        return interaction.reply({ embeds: [queueEmbed(player, interaction.options.getInteger('page') ?? 1)] });
      case 'nowplaying': {
        const song = player.queue.current;
        if (!song) return reply(interaction, 'Nothing is playing.');
        return interaction.reply({ embeds: [nowPlayingEmbed(song, player)] });
      }
      case 'shuffle': {
        const n = player.queue.shuffle();
        return reply(interaction, n > 1 ? `Shuffled ${n} songs.` : 'Not enough songs to shuffle.', n <= 1);
      }
      case 'remove': {
        const removed = player.queue.remove(interaction.options.getInteger('position'));
        return reply(interaction, removed ? `Removed **${removed.title}**.` : 'There is no song at that number. See /queue.', !removed);
      }
      case 'loop': {
        const mode = interaction.options.getString('mode');
        player.queue.loop = mode;
        return reply(interaction, { off: 'Repeat is off.', song: 'Repeating this song.', queue: 'Repeating the queue.' }[mode], false);
      }
    }
  }

  async function play(interaction, player, { next }) {
    const voice = interaction.member.voice.channel;
    if (!voice) return reply(interaction, 'Join a voice channel first.');
    if (player.channelId && player.channelId !== voice.id && player.isPlaying) {
      return reply(interaction, `I'm playing in <#${player.channelId}>. Join it to add songs.`);
    }
    const perms = voice.permissionsFor(interaction.guild.members.me);
    if (!perms?.has(PermissionFlagsBits.Connect) || !perms.has(PermissionFlagsBits.Speak)) {
      return reply(interaction, `I'm not allowed to connect and speak in <#${voice.id}>.`);
    }

    await interaction.deferReply();
    try {
      const found = await songsFor(interaction.options.getString('song'), {
        ytdlp,
        requestedBy: interaction.user.id,
      });
      await player.join(voice);
      player.textChannelId = interaction.channelId;
      const added = player.add(found.songs, { next });
      if (added === 0) return interaction.editReply('The queue is full.');
      if (found.isList) {
        const cut = added < found.songs.length ? ` (the queue is full, so ${found.songs.length - added} were left out)` : '';
        return interaction.editReply(`Added **${added}** songs from **${found.title}**${cut}.`);
      }
      const song = found.songs[0];
      return interaction.editReply(`${next ? 'Playing next' : 'Added'}: **${song.title}**${song.artist ? ` by ${song.artist}` : ''} (${time(song.durationSec)})`);
    } catch (e) {
      return interaction.editReply(`Could not play that: ${e.message}`);
    }
  }

  async function onButton(interaction) {
    const player = players.get(interaction.guild);
    const problem = controlProblem(interaction, player);
    if (problem) return reply(interaction, problem);
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

  return { onCommand, onButton };
}

/** Why this person can't control the music right now, or null if they can. */
function controlProblem(interaction, player) {
  if (!player.channelId) return 'Nothing is playing. Start something with /play.';
  if (interaction.member.voice.channelId !== player.channelId) return `Join <#${player.channelId}> to control the music.`;
  return null;
}

function reply(interaction, content, onlyForYou = true) {
  return interaction.reply({ content, flags: onlyForYou ? MessageFlags.Ephemeral : undefined });
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
