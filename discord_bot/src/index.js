import { spawnSync } from 'node:child_process';
import { createServer } from 'node:http';
import { Client, Events, GatewayIntentBits, MessageFlags } from 'discord.js';
import { commandData, controls, createHandlers, nowPlayingEmbed } from './commands.js';
import { loadConfig } from './config.js';
import { GuildPlayer } from './player.js';
import { YtDlp } from './ytdlp.js';

// View channel, send messages, embed links, connect, speak.
const INVITE_PERMISSIONS = 3165184;

const config = loadConfig();
const ytdlp = new YtDlp({ path: config.ytDlpPath, cookiesFile: config.cookiesFile });
const client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildVoiceStates] });

checkTool('yt-dlp', config.ytDlpPath, ['--version']);
checkTool('ffmpeg', config.ffmpegPath, ['-version']);

/** One player per server, made the first time it is needed. */
const players = {
  byGuild: new Map(),
  get(guild) {
    let player = this.byGuild.get(guild.id);
    if (!player) {
      player = new GuildPlayer({
        guild,
        ytdlp,
        ffmpegPath: config.ffmpegPath,
        maxQueue: config.maxQueue,
        idleMinutes: config.idleMinutes,
      });
      announce(player);
      this.byGuild.set(guild.id, player);
    }
    return player;
  },
};

const handlers = createHandlers({ players, ytdlp });

/** Posts what the player is doing in the channel /play was used in. */
function announce(player) {
  let nowPlaying = null;
  const channel = () => client.channels.cache.get(player.textChannelId);
  const send = async (payload) => {
    try {
      return await channel()?.send(payload);
    } catch (e) {
      console.warn(`Could not post in ${player.guild.name}:`, e.message);
      return null;
    }
  };
  const retireControls = () => {
    nowPlaying?.edit({ components: [] }).catch(() => {});
    nowPlaying = null;
  };

  player.on('start', async (song) => {
    retireControls();
    nowPlaying = await send({ embeds: [nowPlayingEmbed(song, player)], components: [controls(player)] });
  });
  player.on('failed', (song, reason) => send(`Skipped **${song.title}**: ${reason}`));
  player.on('finished', () => {
    retireControls();
    send('That was the last song in the queue.');
  });
  player.on('gaveUp', (reason) => {
    retireControls();
    send(reason);
  });
  player.on('left', (reason) => {
    retireControls();
    if (reason) send(reason);
  });
}

client.once(Events.ClientReady, async (c) => {
  console.log(`Logged in as ${c.user.tag}.`);
  for (const guild of c.guilds.cache.values()) await leaveIfNotAllowed(guild);
  if (config.guildId) {
    const guild = await c.guilds.fetch(config.guildId);
    await guild.commands.set(commandData);
    console.log(`Slash commands ready in ${guild.name}.`);
  } else {
    await c.application.commands.set(commandData);
    console.log('Slash commands registered everywhere (Discord can take up to an hour to show them).');
  }
  console.log(`Invite link: https://discord.com/oauth2/authorize?client_id=${c.user.id}&scope=bot+applications.commands&permissions=${INVITE_PERMISSIONS}`);
});

client.on(Events.GuildCreate, leaveIfNotAllowed);

client.on(Events.InteractionCreate, async (interaction) => {
  if (!interaction.inGuild()) return;
  try {
    if (interaction.isChatInputCommand()) await handlers.onCommand(interaction);
    else if (interaction.isButton() && interaction.customId.startsWith('np:')) await handlers.onButton(interaction);
  } catch (e) {
    console.error(e);
    const content = 'Something went wrong with that.';
    if (interaction.deferred || interaction.replied) await interaction.editReply(content).catch(() => {});
    else await interaction.reply({ content, flags: MessageFlags.Ephemeral }).catch(() => {});
  }
});

// Leaves a channel nobody is listening in, after a short grace period.
client.on(Events.VoiceStateUpdate, (before, after) => {
  const player = players.byGuild.get((after.guild ?? before.guild).id);
  if (!player?.channelId) return;
  if (before.channelId !== player.channelId && after.channelId !== player.channelId) return;
  const channel = after.guild.channels.cache.get(player.channelId);
  const listeners = channel?.members.filter((m) => !m.user.bot).size ?? 0;
  player.setAlone(listeners === 0);
});

async function leaveIfNotAllowed(guild) {
  if (config.allowedGuildIds.length === 0 || config.allowedGuildIds.includes(guild.id)) return;
  console.log(`Leaving ${guild.name} (${guild.id}): not in ALLOWED_GUILD_IDS.`);
  await guild.leave().catch(() => {});
}

function checkTool(name, path, args) {
  const result = spawnSync(path, args, { encoding: 'utf8', windowsHide: true });
  if (result.error) console.warn(`Warning: ${name} was not found at "${path}". Songs will not play until it is installed.`);
  else console.log(`${name} ${result.stdout.split('\n')[0].replace(/^ffmpeg version /, '').split(' ')[0]}`);
}

// Hosts like Render and Koyeb expect a web port; this answers their health checks.
if (process.env.PORT) {
  createServer((req, res) => {
    res.writeHead(client.isReady() ? 200 : 503, { 'Content-Type': 'text/plain' });
    res.end(client.isReady() ? 'ok' : 'starting');
  }).listen(Number(process.env.PORT));
}

function shutdown() {
  for (const player of players.byGuild.values()) player.leave(null);
  client.destroy().finally(() => process.exit(0));
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

await client.login(config.token);
