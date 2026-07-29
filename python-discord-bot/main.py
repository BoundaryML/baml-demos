import asyncio
import discord
from baml_python import baml_sdk
from dotenv import load_dotenv
import os

class Bot(discord.Client):
    async def on_ready(self):
        print(f"{self.user} has connected to Discord!")

    async def on_message(self, message: discord.Message):
        if self.user is None or message.author == self.user:
            return
        if any(x.id == self.user.id for x in message.mentions):
            print(f"{message.author.name} mentioned me")
            thread = await message.create_thread(name=f"{message.author.name}'s thread")

            async with thread.typing():
                tasks = []
                loop = asyncio.get_event_loop()
                try:
                    response = baml_sdk.respond(
                        baml_sdk.DiscordMessage(
                            from_user=message.author.name,
                            content=message.content,
                        ),
                        lambda: tasks.append(loop.create_task(message.delete())),
                        lambda update: tasks.append(loop.create_task(thread.send(update))),
                    )
                except Exception as e:
                    await thread.send(f"An error occurred while processing your message. Please try again later.\n{e}")
                    return
                while len(response) > 2000:
                    await thread.send(response[:2000])
                    response = response[2000:]
                await thread.send(response)

def main():
    intents = discord.Intents.default()
    intents.message_content = True
    bot = Bot(intents=intents)
    load_dotenv()
    discord_token = os.getenv("DISCORD_TOKEN")
    if discord_token is None:
        raise ValueError("DISCORD_TOKEN environment variable not set")
    bot.run(discord_token)

if __name__ == "__main__":
    main()
