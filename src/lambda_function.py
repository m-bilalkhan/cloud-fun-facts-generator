import boto3
import random
import json


# DynamoDB connection
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("CloudFacts")


# Bedrock client
bedrock = boto3.client("bedrock-runtime")


def lambda_handler(event, context):
    # Fetch all facts from DynamoDB
    response = table.scan()
    items = response.get("Items", [])
    if not items:
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type"
            },
            "body": json.dumps({"fact": "No facts available in DynamoDB."})
        }


    fact = random.choice(items)["FactText"]

    messages = f"Take this cloud computing fact and make it fun and engaging in 1-2 sentences maximum. Keep it short and witty: {fact}"

    body = {
        "inputText": messages,
        "textGenerationConfig": {
            "maxTokenCount": 100,
            "temperature": 0.7
        }
    }


    try:
        resp = bedrock.invoke_model(
            modelId="amazon.titan-text-lite-v1",
            body=json.dumps(body),
            accept="application/json",
            contentType="application/json"
        )


        # Parse response
        result = json.loads(resp["body"].read())
        witty_fact = ""


        if "results" in result and len(result["results"]) > 0:
            witty_fact = result["results"][0].get("outputText", "").strip()

        # Fallback if empty or too long
        if not witty_fact or len(witty_fact) > 300:
            witty_fact = fact


    except Exception as e:
        print(f"Bedrock error: {e}")
        witty_fact = fact


    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type"
        },
        "body": json.dumps({"fact": witty_fact})
    }