# agent_download_compress.py
import yt_dlp
import subprocess
import os
import git

repo_path = r"D:\ai-videos"
output_dir = repo_path
os.makedirs(output_dir, exist_ok=True)

def download_and_compress(video_url, output_name):
    # 1.下载视频
    ydl_opts = {
        'outtmpl': os.path.join(output_dir, f"{output_name}.tmp"),
    }
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        ydl.download([video_url])

    tmp_file = os.path.join(output_dir, f"{output_name}.tmp")
    out_file = os.path.join(output_dir, f"{output_name}.mp4")
    txt_file = os.path.join(output_dir, f"{output_name}.txt")

    # 2.FFmpeg压缩转mp4
    cmd = [
        "ffmpeg", "-i", tmp_file,
        "-crf", "28", "-preset", "fast",
        "-c:a", "aac", "-b:a", "128k",
        "-y", out_file
    ]
    subprocess.run(cmd)
    os.remove(tmp_file)

    # 自动生成txt元信息模板
    template_content = """这里填写视频标题
这里填写视频分类
这里填写完整AI提示词，支持多行
"""
    with open(txt_file, "w", encoding="utf-8") as f:
        f.write(template_content)
    print(f"📄 已自动生成元信息模板文件：{output_name}.txt，请打开填写内容！")

    # git推送mp4
    repo = git.Repo(repo_path)
    repo.index.add([out_file])
    repo.index.commit(f"add video {output_name}.mp4")
    repo.remotes.origin.push("main")
    print(f"✅ {output_name}.mp4 已上传到 ai-videos")

if __name__ == "__main__":
    url = input("输入视频链接：")
    name = input("视频编号（例如 s000035）：")
    download_and_compress(url, name)
