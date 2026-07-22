import torch
from transformers import AutoTokenizer, AutoModelForMaskedLM
from transformers.utils import logging as transformers_logging


# model_id = 'hfl/chinese-roberta-wwm-ext-large'
local_path = "./bert/chinese-roberta-wwm-ext-large"


tokenizers = {}
models = {}

def get_bert_feature(text, word2ph, device=None, model_id='hfl/chinese-roberta-wwm-ext-large'):
    device = device or "cpu"
    if model_id not in models:
        # This pretrained BERT checkpoint also contains pooler/NSP tensors that
        # AutoModelForMaskedLM does not consume. They are irrelevant because MeloTTS
        # only reads an encoder hidden state, so suppress the expected load report
        # while preserving real exceptions.
        previous_verbosity = transformers_logging.get_verbosity()
        progress_enabled = transformers_logging.is_progress_bar_enabled()
        try:
            transformers_logging.set_verbosity_error()
            transformers_logging.disable_progress_bar()
            models[model_id] = AutoModelForMaskedLM.from_pretrained(
                model_id,
                local_files_only=True,
            ).to(device)
            tokenizers[model_id] = AutoTokenizer.from_pretrained(
                model_id,
                local_files_only=True,
                fix_mistral_regex=True,
            )
        finally:
            transformers_logging.set_verbosity(previous_verbosity)
            if progress_enabled:
                transformers_logging.enable_progress_bar()
    model = models[model_id]
    tokenizer = tokenizers[model_id]

    with torch.no_grad():
        inputs = tokenizer(text, return_tensors="pt")
        for i in inputs:
            inputs[i] = inputs[i].to(device)
        res = model(**inputs, output_hidden_states=True)
        res = torch.cat(res["hidden_states"][-3:-2], -1)[0].cpu()
    # import pdb; pdb.set_trace()
    # assert len(word2ph) == len(text) + 2
    word2phone = word2ph
    phone_level_feature = []
    for i in range(len(word2phone)):
        repeat_feature = res[i].repeat(word2phone[i], 1)
        phone_level_feature.append(repeat_feature)

    phone_level_feature = torch.cat(phone_level_feature, dim=0)
    return phone_level_feature.T


if __name__ == "__main__":
    import torch

    word_level_feature = torch.rand(38, 1024)  # 12个词,每个词1024维特征
    word2phone = [
        1,
        2,
        1,
        2,
        2,
        1,
        2,
        2,
        1,
        2,
        2,
        1,
        2,
        2,
        2,
        2,
        2,
        1,
        1,
        2,
        2,
        1,
        2,
        2,
        2,
        2,
        1,
        2,
        2,
        2,
        2,
        2,
        1,
        2,
        2,
        2,
        2,
        1,
    ]

    # 计算总帧数
    total_frames = sum(word2phone)
    print(word_level_feature.shape)
    print(word2phone)
    phone_level_feature = []
    for i in range(len(word2phone)):
        print(word_level_feature[i].shape)

        # 对每个词重复word2phone[i]次
        repeat_feature = word_level_feature[i].repeat(word2phone[i], 1)
        phone_level_feature.append(repeat_feature)

    phone_level_feature = torch.cat(phone_level_feature, dim=0)
    print(phone_level_feature.shape)  # torch.Size([36, 1024])
